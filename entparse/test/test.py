import json
import entparse

def test_parse_extent():
    vals = [
        [1,'2',[3]],
        {'a':1, 'b':2, 'c':3}
    ]
    for val in vals:
        print entparse.JEBExtent.parse(json.dumps(val))
    raise NotImplementedError

def test_parse_extent_unicode():
    raise NotImplementedError

def test_jeblist():
    raise NotImplementedError

def test_jebdict():
    raise NotImplementedError

def test_char_iterator():
    res = []
    citer = entparse.CharIterator('abc')
    for i, c in citer:
        print i, c
        if i == 1 and len(res) < 2:
            citer.rerun()
        res.append(c)
    assert res == ['a','b','b','c']
