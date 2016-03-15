cimport entparse

cdef class JEBExtent:
    pass

cdef class JEBEntity:
    pass

cdef entparse.JEBExtent parse_extent(str string, unsigned int offset):
    raise NotImplementedError

cdef class JEBList(JEBEntity):
    def __getitem__(self, unsigned int index):
        raise NotImplementedError

cdef class JEBDict(JEBEntity):
    def __getitem__(self, basestring key):
        raise NotImplementedError
