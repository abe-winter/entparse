## entparse

The json entity parser. This is a cython library that can be used from python or cython to do fast parsing of json entities.

### what's an entity?

* every item you parse has the same fields or fields from a small-ish, known set
* object structures aren't extremely deep
* for a given field (array position or dictionary key) the type is usually the same
* not to be confused with SGML (XML, HTML) entities like `&amp;`

### intended use case

* loading lots of json items into cython objects (cython objects for memory efficiency and initialization speed)
* when json items have known schema
