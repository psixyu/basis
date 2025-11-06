local basis = require('basis') --[[@as basis]]

basis.lib({
	loader = basis.loader.path('basis/test/require/lib2'),
})

return {
	user = 'test',
	name = 'lib3',
	version = '2.1.0',
}