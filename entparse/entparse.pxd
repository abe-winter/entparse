cdef enum ParserState:
    # note: post_comma and pre_comma can only appear directly above a dict_outer or list_outer
    post_comma
    begin_val
    top, dict_outer, list_outer, double_quote, single_quote, backslash, list_value, pre_float, post_float,
    dict_key, dict_sep
    not_set

cdef struct JEBExtent:
    unsigned int a
    unsigned int b
    ParserState type

cdef class ExtentList:
    cdef unsigned int n
    cdef unsigned int width
    cdef JEBExtent* _extents

    cdef void clear(self)
    cdef void set(self, unsigned int i, unsigned int a, unsigned int b, ParserState state)
    cdef void push(self, unsigned int a, unsigned int b, ParserState state)

cdef class ParseOutput:
    cdef ExtentList keys
    cdef ExtentList values

    cdef void clear(self)
    # todo: figure out default verbose=False
    cpdef void parse(self, str string, bint verbose)
