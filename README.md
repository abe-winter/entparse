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

### correctness issues

* this doesn't validate and there are known bad strings that it will probably parse
* not widely tested otherwise

### how fast is this?

It's marginally faster than ujson in a contrived benchmark but *may* be significantly faster if your goal is to load data from JSON to cython structs.

Benchmark:

library | condition | seconds
---|---|---
json | from cpython | 0.933
ujson | from cpython | 0.165
ujson | from cython | not tested
entparse | from cpython | 0.147
entparse | from cython | 0.125

Note: this isn't a fair benchmark. entparse isn't doing anything but bounds-checking at the outer level.
