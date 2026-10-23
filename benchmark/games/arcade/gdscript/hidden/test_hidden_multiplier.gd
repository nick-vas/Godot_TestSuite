extends GutTest
## Hidden check for the prototype's fix-bug: the fifth hit in a row doubles, the tenth triples.


func test_hidden_fifth_hit_doubles():
	var score := Score.new()
	for i in 4:
		score.hit(10)
	assert_eq(score.hit(10), 20)


func test_hidden_tenth_hit_triples():
	var score := Score.new()
	for i in 9:
		score.hit(10)
	assert_eq(score.hit(10), 30)
