## entparse

The json entity parser. This is a cython library that can be used from python or cython to do fast parsing of json entities.

### what's an entity?

* every item you parse has the same fields or fields from a small-ish, known set
* object structures aren't extremely deep
* for a given field (array position or dictionary key) the type is usually the same

### why is this faster?

* when you use entparse from normal python, you skip all the mallocs
* in cython:
    * you can `cimport` entparse and use the optimized entity object directly
    * postpone value parsing (except for extents) to as late as possible so you can populate cython structs directly (no intermediate python object)

### intended use case

* loading lots of json items into cython objects (cython objects for memory efficiency and initialization speed)
* json items have known schema

