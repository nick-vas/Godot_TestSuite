# Misuses Vulkan on purpose, in a way Godot's RenderingDevice does not check but the validation layer does: a compute
# shader writes a uimage2D (unsigned integers) bound to an R32_SFLOAT texture (floats), which is
# VUID-vkCmdDispatch-format-07753. Without --gpu-validation nothing is reported and the game runs as if nothing were wrong.
extends Node3D

const SOURCE := """
#version 450
layout(local_size_x = 1, local_size_y = 1) in;
layout(set = 0, binding = 0, r32ui) uniform restrict writeonly uimage2D target;
void main() { imageStore(target, ivec2(gl_GlobalInvocationID.xy), uvec4(1)); }
"""


func _ready() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return   # OpenGL or headless: nothing to misuse.
	var source := RDShaderSource.new()
	source.source_compute = SOURCE
	var shader := rd.shader_create_from_spirv(rd.shader_compile_spirv_from_source(source))
	var format := RDTextureFormat.new()
	format.width = 4
	format.height = 4
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var texture := rd.texture_create(format, RDTextureView.new())
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture)
	var uniforms := rd.uniform_set_create([uniform], shader, 0)
	var pipeline := rd.compute_pipeline_create(shader)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniforms, 0)
	rd.compute_list_dispatch(list, 4, 4, 1)
	rd.compute_list_end()
	await get_tree().process_frame
	await get_tree().process_frame
	for rid in [pipeline, uniforms, texture, shader]:
		rd.free_rid(rid)
