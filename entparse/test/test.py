import json, pytest
import entparse

def test_list_container():
    val = [1.1, '2', [3]]
    assert val == entparse.JEBExtent.parse(json.dumps(val), True).tolist()

def test_dict_container():
    # todo: make this list actually a list
    val = {'a':1, 'b':[1,2], 'c':"x"}
    assert val == entparse.JEBExtent.parse(json.dumps(val), True).todict()

@pytest.mark.xfail
def test_parse_unicode():
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

    with pytest.raises(entparse.RerunError):
        citer = entparse.CharIterator('abc')
        for _ in citer:
            citer.rerun()
