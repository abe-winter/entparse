"shared declarations for jebuil types and functions"

cdef class JEBExtent:
    cdef public slice slice
    cdef public type type

# todo: can this be a classmethod in pxd?
cdef JEBExtent parse_extent(str string, unsigned int offset)

cdef class JEBEntity:
    pass

cdef class JEBList(JEBEntity):
    cdef public int maxwidth

    cpdef __getitem__(self, unsigned int index)

cdef class JEBDict(JEBEntity):
    cdef public list fields

    cpdef __getitem__(self, basestring key)
