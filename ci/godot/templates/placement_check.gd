# Checks every placed object in a level against the limits the gameplay code itself uses, so a moved prop, a re-baked
# navmesh or a changed constant fails the next test run instead of turning up in a bug report. Copy this file into the
# game's test folder; it depends on no test framework (godot-data skill, "Placed objects").
#
#   const PlacementCheck := preload("res://test/placement_check.gd")
#   const Player := preload("res://player.gd")
#   const ZipLine := preload("res://zipline.gd")
#   func test_every_level() -> void:
#       var check := PlacementCheck.new()
#       check.reach = Player.REACH                      # read from gameplay code, never copied
#       check.zipline_max_angle = ZipLine.MAX_ANGLE_DEGREES
#       var findings: Array[String] = await check.check_scenes(self, PlacementCheck.scenes_in("res://levels"))
#       gut.p(check.summary())
#       assert_true(findings.is_empty(), check.report())
#
# Rules, by node group (a node may be in several):
#   ai_point      navmesh_below    navmesh at most ai_nav_max_drop (0.5 m) straight below the node
#                 path_to_link     a navmesh path reaches each node in its `links` metadata (an Array of NodePath)
#   interactable  ground_in_reach  a ray straight down finds ground within `reach`
#   zipline       zipline_clear    `clearance` swept from the node to its `End` child, `hang` below the rope, hits nothing
#                 zipline_angle    the rope's angle from horizontal is at most `zipline_max_angle` degrees
#   landmark      landmark_still   not a moving body, not under a PathFollow3D, and did not move while watched
#                 landmark_seen    seen from at least `min_sightings` separate stretches of the level's routes
#   route         landmark_ahead   walked each way, a landmark is in view ahead on at least `min_ahead_share` of it
# Wayfinding (godot-game-design, "Levels players find their way in"): a route is a Path3D the player travels, walked
# both ways unless its metadata says one_way = true. From points `route_step` apart, at `eye_height`, a landmark is seen
# when it is within `view_fov` of the way the player walks and a ray to it hits nothing; the ray aims at the landmark's
# Marker3D children (the top of a tower), or at its origin when it has none. Only what has collision hides a landmark.
# Exempt one node from one rule with the metadata placement_skip = {"rule": "reason"}. Exemptions are listed in the
# summary; one without a reason is itself a finding. Each finding is one line:
#   <scene> <node path> (<x>, <y>, <z>) <rule>: <measured value> (limit <limit>)
extends RefCounted

const GROUPS: Array[String] = ["ai_point", "interactable", "zipline", "landmark", "route"]

# Limits. The two without a default must come from gameplay code; a rule whose limit is unset reports that instead.
var reach := -1.0                  # metres from an interactable down to the ground the player stands on
var zipline_max_angle := -1.0      # degrees from horizontal the zip-line movement handles
var ai_nav_max_drop := 0.5         # metres from an ai_point down to the navmesh
var nav_side_tolerance := 0.1      # metres the navmesh point may be beside the ai_point instead of straight below it
var path_tolerance := 0.5          # metres a path's end may stop short of the linked point
var clearance: Shape3D = null      # what must pass under the rope; a 0.4 m x 1.8 m capsule when null
var hang := 1.3                    # metres from the rope down to the centre of `clearance`
var zipline_end := NodePath("End")
var ground_search := 50.0          # how far down to look for ground, so a miss still reports how far it is
var collision_mask := 0xFFFFFFFF
var max_wait_frames := 120         # physics frames to wait for navigation before giving up
var eye_height := 1.6              # metres from a route up to the camera; read it from the player's camera
var view_fov := 90.0               # degrees, horizontal, of the view ahead in which a landmark counts as seen
var sight_range := 4000.0          # metres a landmark can be seen from (Camera3D's default far plane)
var route_step := 2.0              # metres between the points sampled along a route
var min_sightings := 2             # separate stretches of route each landmark is seen from; once is not a reference
var min_ahead_share := 0.25        # share of a route, each way it is walked, with a landmark in view ahead
var still_frames := 30             # physics frames check_scenes watches each landmark for movement
var still_tolerance := 0.01        # metres a landmark may move while watched
var counts_file := ""              # where per-group counts are kept, for the change since the last run ("" = none)

var findings: Array[String] = []
var exemptions: Array[String] = []
var ready_frames: Array[int] = []  # physics frames each level needed before navigation answered

var _counts := {}                  # group -> {checked, findings, exempt}
var _previous := {}                # group -> findings in the last run, from counts_file
var _scene := ""
var _level: Node = null
var _moved := {}                   # landmark -> metres it moved while watched
var _walks := []                   # per route and way walked: {route, way, length, share, seen: {landmark: [[from, to]]}}
var _route_count := 0
var _wayfinding: Array[String] = []  # summary lines: what each landmark is seen from, how much of each route sees one


# Every .tscn under dir, skipping folders with a .gdignore.
static func scenes_in(dir: String) -> Array[String]:
	var found: Array[String] = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			found.append_array(scenes_in(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			found.append(dir.path_join(file))
	found.sort()
	return found


# Instantiates each scene under parent (which must be in the tree), waits for navigation, checks it and frees it.
func check_scenes(parent: Node, paths: Array[String]) -> Array[String]:
	_load_counts()
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			findings.append("%s: does not load" % path)
			continue
		var level := packed.instantiate()
		parent.add_child(level)
		_scene = path
		if await wait_until_ready(level):
			await _watch_landmarks(level)
			check_level(level, path)
		_moved.clear()
		parent.remove_child(level)
		level.free()
	_save_counts()
	return findings


# Waits until the navigation map answers for every NavigationRegion3D in the level. On Godot 4.7.2 headless that took
# 4 or 5 physics frames for one region; a query before the first map sync prints an engine error, so poll, with a cap.
func wait_until_ready(level: Node) -> bool:
	var map := _map(level)
	var probes := []  # [region rid, a point on its navmesh]
	for region in level.find_children("*", "NavigationRegion3D", true, false):
		var mesh: NavigationMesh = region.navigation_mesh
		if region.enabled and mesh and mesh.get_polygon_count() > 0:
			var centre := Vector3.ZERO
			var polygon := mesh.get_polygon(0)
			for i in polygon:
				centre += mesh.get_vertices()[i]
			probes.append([region.get_rid(), region.global_transform * (centre / polygon.size())])
	for frame in max_wait_frames:
		await level.get_tree().physics_frame
		if _navigation_answers(map, probes):
			ready_frames.append(frame + 1)
			return true
	findings.append("%s: navigation did not answer within %d physics frames" % [_scene, max_wait_frames])
	return false


# Checks one level that is in the tree and whose navigation is ready; findings are appended.
func check_level(level: Node, scene_path: String) -> void:
	_scene = scene_path
	_level = level
	_walk_routes(level)
	for group in GROUPS:
		if not _counts.has(group):
			_counts[group] = {"checked": 0, "findings": 0, "exempt": 0}
		for node in _in_level(level, group):
			_counts[group].checked += 1
			call("_check_" + group, node, group)


# Watches the level's landmarks for still_frames physics frames: a creature, a drifting balloon or an animated prop
# moves, and a landmark that moves cannot anchor a player's mental map.
func _watch_landmarks(level: Node) -> void:
	_moved.clear()
	var start := {}
	for node in _in_level(level, "landmark"):
		start[node] = node.global_position
	if start.is_empty():
		return
	for frame in still_frames:
		await level.get_tree().physics_frame
	for node in start:
		_moved[node] = node.global_position.distance_to(start[node])


# All findings as one block: the failure message of a test.
func report() -> String:
	var per_group: Array[String] = []
	for group in GROUPS:
		if _counts.has(group) and _counts[group].findings > 0:
			per_group.append("%s %d" % [group, _counts[group].findings])
	return "%d placement finding(s) (%s)\n%s\n%s" % [findings.size(), ", ".join(per_group), "\n".join(findings), summary()]


# One line per group with the change since the last run, then every exemption.
func summary() -> String:
	var lines: Array[String] = []
	for group in GROUPS:
		if not _counts.has(group):
			continue
		var c: Dictionary = _counts[group]
		if c.checked == 0 and not _previous.has(group):
			continue
		var change := ""
		if _previous.has(group):
			change = " (%+d since the last run)" % (c.findings - int(_previous[group]))
		lines.append("%s: %d checked, %d finding(s)%s, %d exempt" % [group, c.checked, c.findings, change, c.exempt])
	for line in _wayfinding:
		lines.append("wayfinding: " + line)
	for line in exemptions:
		lines.append("exempt: " + line)
	if not ready_frames.is_empty():
		lines.append("navigation answered after %s physics frames" % ", ".join(ready_frames.map(func(f): return str(f))))
	return "\n".join(lines)


func _check_ai_point(node: Node3D, group: String) -> void:
	var map := _map(node)
	var pos := node.global_position
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		_add(node, group, "navmesh_below", "the level has no navigation map")
		return
	if not _skipped(node, group, "navmesh_below"):
		var on_mesh := NavigationServer3D.map_get_closest_point(map, pos)
		var up := NavigationServer3D.map_get_up(map)
		var drop := (pos - on_mesh).dot(up)
		var side := ((pos - on_mesh) - up * drop).length()
		if side > nav_side_tolerance:
			_add(node, group, "navmesh_below", "none below; nearest %.2f m to the side (limit %.2f m)" % [side, nav_side_tolerance])
		elif drop < -nav_side_tolerance:
			_add(node, group, "navmesh_below", "navmesh %.2f m above the point (limit: below it)" % -drop)
		elif drop > ai_nav_max_drop:
			_add(node, group, "navmesh_below", "navmesh %.2f m below (limit %.2f m)" % [drop, ai_nav_max_drop])
	var links: Array = node.get("links") if "links" in node else node.get_meta("links", [])
	for link in links:
		if _skipped(node, group, "path_to_link"):
			break
		var target := node.get_node_or_null(link) as Node3D
		if target == null:
			_add(node, group, "path_to_link", "link %s does not exist" % link)
			continue
		var from := NavigationServer3D.map_get_closest_point(map, pos)
		var to := NavigationServer3D.map_get_closest_point(map, target.global_position)
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var gap := from.distance_to(to) if path.is_empty() else path[path.size() - 1].distance_to(to)
		if gap > path_tolerance:
			_add(node, group, "path_to_link", "path to %s stops %.2f m short (limit %.2f m)" % [_level.get_path_to(target), gap, path_tolerance])


func _check_interactable(node: Node3D, group: String) -> void:
	if _skipped(node, group, "ground_in_reach"):
		return
	if reach < 0.0:
		_add(node, group, "ground_in_reach", "reach is not set; read it from the player's code")
		return
	var from := node.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ground_search, collision_mask, _own_rids(node))
	var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_add(node, group, "ground_in_reach", "no ground within %.2f m below (limit %.2f m)" % [ground_search, reach])
	elif from.distance_to(hit.position) > reach:
		_add(node, group, "ground_in_reach", "ground %.2f m below (limit %.2f m)" % [from.distance_to(hit.position), reach])


func _check_zipline(node: Node3D, group: String) -> void:
	var end := node.get_node_or_null(zipline_end) as Node3D
	if end == null:
		_add(node, group, "zipline_clear", "no %s child marks the far end" % zipline_end)
		return
	var a := node.global_position
	var b := end.global_position
	if not _skipped(node, group, "zipline_angle"):
		var angle := rad_to_deg(atan2(absf(b.y - a.y), Vector2(b.x - a.x, b.z - a.z).length()))
		if zipline_max_angle < 0.0:
			_add(node, group, "zipline_angle", "zipline_max_angle is not set; read it from the movement code")
		elif angle > zipline_max_angle:
			_add(node, group, "zipline_angle", "%.1f degrees (limit %.1f)" % [angle, zipline_max_angle])
	if _skipped(node, group, "zipline_clear"):
		return
	var query := PhysicsShapeQueryParameters3D.new()
	if clearance == null:
		clearance = CapsuleShape3D.new()
		clearance.radius = 0.4
		clearance.height = 1.8
	query.shape = clearance
	query.collision_mask = collision_mask
	query.exclude = _own_rids(node)
	query.transform = Transform3D(Basis(), a + Vector3.DOWN * hang)
	query.motion = b - a
	var space := node.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)  # [safe, unsafe]; [1, 1] when nothing is in the way
	if fractions[1] >= 1.0:
		return
	query.transform.origin += query.motion * fractions[1]
	var blockers: Array[String] = []
	for hit in space.intersect_shape(query, 4):
		blockers.append(str(_level.get_path_to(hit.collider)) if hit.collider is Node else str(hit.rid))
	_add(node, group, "zipline_clear", "blocked by %s at %d%% of %.1f m (limit: clear all the way)"
		% [", ".join(blockers) if not blockers.is_empty() else "something", roundi(fractions[1] * 100.0), a.distance_to(b)])


func _check_landmark(node: Node3D, group: String) -> void:
	if not _skipped(node, group, "landmark_still"):
		var moving := _moving(node)
		if not moving.is_empty():
			_add(node, group, "landmark_still", moving)
			return
	var stretches := 0
	var parts: Array[String] = []
	for walk in _walks:
		var runs: Array = walk.seen.get(node, [])
		if runs.is_empty():
			continue
		stretches += runs.size()
		parts.append("%s %s at %s" % [_level.get_path_to(walk.route), _way(walk.way),
			" and ".join(runs.map(func(r): return "%d-%d m" % [roundi(r[0]), roundi(r[1])]))])
	var seen := "seen %d time(s)%s" % [stretches, (": " + "; ".join(parts)) if not parts.is_empty() else ""]
	_wayfinding.append("%s %s: %s" % [_scene, _level.get_path_to(node), seen])
	if _skipped(node, group, "landmark_seen"):
		return
	if _route_count == 0:
		_add(node, group, "landmark_seen", "the level has no route (a Path3D in group route) to see it from")
	elif stretches < min_sightings:
		_add(node, group, "landmark_seen", "%s (limit %d)" % [seen, min_sightings])


func _check_route(node: Node3D, group: String) -> void:
	var path := node as Path3D
	if path == null or path.curve == null or path.curve.get_baked_length() <= 0.0:
		_add(node, group, "landmark_ahead", "not a Path3D with a curve (limit: a Path3D the player travels)")
		return
	var shares: Array[String] = []
	var short: Array = []
	for walk in _walks:
		if walk.route == node:
			shares.append("%d%% %s" % [roundi(walk.share * 100.0), _way(walk.way)])
			if walk.share < min_ahead_share:
				short.append(walk)
	var one_way := " (one way)" if path.get_meta("one_way", false) else ""
	_wayfinding.append("%s %s: a landmark ahead on %s%s" % [_scene, _level.get_path_to(node), ", ".join(shares), one_way])
	if _skipped(node, group, "landmark_ahead"):
		return
	for walk in short:
		_add(node, group, "landmark_ahead", "%s, a landmark ahead on %d%% of %.0f m (limit %d%%)"
			% [_way(walk.way), roundi(walk.share * 100.0), walk.length, roundi(min_ahead_share * 100.0)])


# Walks every route of the level each way it is travelled and records, per point, which landmarks are in view ahead.
# What can be seen from a point does not depend on the way the route is walked; what is ahead does, which is why a
# route that is easy to follow out can lose the player on the way back.
func _walk_routes(level: Node) -> void:
	_walks.clear()
	var routes := _in_level(level, "route")
	_route_count = routes.size()
	var landmarks := []  # [node, aim points, own collision]
	for node in _in_level(level, "landmark"):
		var skip: Dictionary = node.get_meta("placement_skip", {})
		if not _moving(node).is_empty() and not skip.has("landmark_still"):
			continue
		var aims: Array[Vector3] = []
		for child in node.get_children():
			if child is Marker3D:
				aims.append(child.global_position)
		if aims.is_empty():
			aims.append(node.global_position)
		landmarks.append([node, aims, _own_rids(node)])
	var space := level.get_viewport().find_world_3d().direct_space_state
	for route in routes:
		var path := route as Path3D
		if path == null or path.curve == null or path.curve.get_baked_length() <= 0.0:
			continue  # _check_route reports it
		var length := path.curve.get_baked_length()
		var steps := maxi(ceili(length / route_step), 1)
		var points: Array[Vector3] = []
		for i in steps + 1:
			points.append(path.global_transform * path.curve.sample_baked(length * i / steps))
		var in_sight := []  # per point: [[landmark, flat direction to an aim point it is seen at]]
		for p in points:
			var eye := p + Vector3.UP * eye_height
			var row := []
			for mark in landmarks:
				for aim in mark[1]:
					if eye.distance_to(aim) > sight_range:
						continue
					var ray := PhysicsRayQueryParameters3D.create(eye, aim, collision_mask, mark[2])
					if space.intersect_ray(ray).is_empty():
						row.append([mark[0], Vector2(aim.x - eye.x, aim.z - eye.z)])
			in_sight.append(row)
		for way in ([1] if path.get_meta("one_way", false) else [1, -1]):
			var seen := {}
			var last := {}  # landmark -> index of the walk's last point it was seen from
			var ahead := 0
			for k in points.size():
				var i: int = k if way == 1 else points.size() - 1 - k
				# The way the player walks at this point: towards the next point, or from the previous one at the end.
				var a := points[i] if k < points.size() - 1 else points[i - way]
				var b := points[i + way] if k < points.size() - 1 else points[i]
				var heading := Vector2(b.x - a.x, b.z - a.z)
				var any := false
				for entry in in_sight[i]:
					var mark: Node = entry[0]
					var to: Vector2 = entry[1]
					if heading.length() < 0.001 or to.length() < 0.01 or absf(heading.angle_to(to)) > deg_to_rad(view_fov) / 2.0:
						continue
					any = true
					if last.get(mark, -2) == k:
						continue  # already counted at this point through another aim point
					var at := length * k / steps
					if last.get(mark, -2) == k - 1:
						seen[mark][-1][1] = at
					else:
						if not seen.has(mark):
							seen[mark] = []
						seen[mark].append([at, at])
					last[mark] = k
				if any:
					ahead += 1
			_walks.append({"route": path, "way": way, "length": length, "share": float(ahead) / points.size(), "seen": seen})


# Why a landmark is not stationary, as a finding's measured value; empty when it is.
func _moving(node: Node3D) -> String:
	var n: Node = node
	while n != null:
		if n is CharacterBody3D or n is AnimatableBody3D or (n is RigidBody3D and not (n as RigidBody3D).freeze):
			return "%s%s (limit: stationary)" % ["a " if n == node else "under %s, a " % _level.get_path_to(n), n.get_class()]
		if n is PathFollow3D:
			return "under %s, a PathFollow3D (limit: stationary)" % _level.get_path_to(n)
		if n == _level:
			break
		n = n.get_parent()
	if _moved.get(node, 0.0) > still_tolerance:
		return "moved %.2f m in %d physics frames (limit %.2f m)" % [_moved[node], still_frames, still_tolerance]
	return ""


func _way(way: int) -> String:
	return "start to end" if way == 1 else "end to start"


func _in_level(level: Node, group: String) -> Array:
	var nodes := []
	for node in level.get_tree().get_nodes_in_group(group):
		if node is Node3D and (node == level or level.is_ancestor_of(node)):
			nodes.append(node)
	return nodes


func _skipped(node: Node, group: String, rule: String) -> bool:
	var skip: Dictionary = node.get_meta("placement_skip", {})
	if not skip.has(rule):
		return false
	var reason := str(skip[rule]).strip_edges()
	if reason.is_empty():
		_add(node, group, rule, "exempt without a reason; placement_skip needs one")
		return false
	exemptions.append("%s %s %s: %s" % [_scene, _level.get_path_to(node), rule, reason])
	_counts[group].exempt += 1
	return true


func _add(node: Node3D, group: String, rule: String, measured: String) -> void:
	var p := node.global_position
	findings.append("%s %s (%.2f, %.2f, %.2f) %s: %s" % [_scene, _level.get_path_to(node), p.x, p.y, p.z, rule, measured])
	_counts[group].findings += 1


func _navigation_answers(map: RID, probes: Array) -> bool:
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return probes.is_empty()
	# Before a region is in the map, the closest point is (0, 0, 0) with no owner: compare the owner, not only the point.
	for probe in probes:
		if NavigationServer3D.region_get_iteration_id(probe[0]) == 0:
			return false
		if not NavigationServer3D.map_get_closest_point_owner(map, probe[1]).is_valid():
			return false
		if NavigationServer3D.map_get_closest_point(map, probe[1]).distance_to(probe[1]) > 0.05:
			return false
	return true


func _map(node: Node) -> RID:
	return node.get_viewport().find_world_3d().navigation_map


# The node's own collision objects, so a torch's bracket or a zip line's posts never count as ground or obstacle.
func _own_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	for body in node.find_children("*", "CollisionObject3D", true, false):
		rids.append(body.get_rid())
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	return rids


func _load_counts() -> void:
	if counts_file.is_empty() or not FileAccess.file_exists(counts_file):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(counts_file))
	if parsed is Dictionary:
		_previous = parsed


func _save_counts() -> void:
	if counts_file.is_empty():
		return
	var now := {}
	for group in _counts:
		now[group] = _counts[group].findings
	var file := FileAccess.open(counts_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(now))
