local basis = require('basis') --[[@as basis]]

basis.lib({
	loader = basis.loader.path('basis/test/require/lib1_1'),
})

return {
	user = 'test',
	name = 'lib4',
	version = '1.2.3',
}