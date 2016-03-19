import json, pytest
import entparse

def test_list_container():
    test_list = [1, '2', [3]]
    comparison = [json.loads(v.value()) for v in entparse.JEBExtent.parse(json.dumps(test_list), True).values]
    assert test_list == comparison

@pytest.mark.xfail
def test_dict_container():
    raise NotImplementedError
    # {'a':1, 'b':2, 'c':3},

@pytest.mark.xfail
def test_parse_extent_unicode():
    raise NotImplementedError

@pytest.mark.xfail
def test_jeblist():
    raise NotImplementedError

@pytest.mark.xfail
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
