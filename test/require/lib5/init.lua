local basis = require('basis') --[[@as basis]]

basis.lib({
	loader = basis.loader.path('basis/test/require/lib3'),
})

return {
	user = 'test',
	name = 'lib5',
	version = '1.0.0',
}