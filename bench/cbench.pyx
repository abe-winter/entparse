cimport entparse

def loop(str blob, unsigned int n):
    cdef entparse.ParseOutput parser = entparse.ParseOutput()
    cdef int i = 0
    while i < n:
        parser.parse(blob, False)
        i += 1
