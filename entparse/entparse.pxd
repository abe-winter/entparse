cdef class ExtentList:
    cdef unsigned int n
    cdef list _extents

    cdef clear(self)
    cdef push(self, slice slice, type type)

cdef class ParseOutput:
    cdef ExtentList keys
    cdef ExtentList values

    cdef clear(self)
    # todo: figure out default verbose=False
    cpdef void parse(self, str string, bint verbose)
