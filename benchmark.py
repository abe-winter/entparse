"benchmark.py -- parsing speed tests"

import json, ujson, entparse, time, contextlib, cython

@contextlib.contextmanager
def timer(name):
    t0 = time.time()
    yield t0
    print '%s %.3fs' % (name, time.time() - t0)

def inline_loop(blob, n):
    return cython.inline("""
        cdef int i = 0
        while i < n:
            entparse.JEBExtent.parse(blob)
            i += 1
        """)

def main():
    blob = json.dumps({'a':1, 'b':2, 'c':[1,2,3,4,5], 'd':{1:2, 3:4}})
    n = 100000
    print 'n', n
    with timer('json'):
        for _ in xrange(n):
            json.loads(blob)
    with timer('ujson'):
        for _ in xrange(n):
            ujson.loads(blob)
    with timer('entparse'):
        for _ in xrange(n):
            entparse.JEBExtent.parse(blob)
    for i in range(2):
        with timer('entparse_inline'):
            inline_loop(blob, n)

if __name__ == '__main__': main()
