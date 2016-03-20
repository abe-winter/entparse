import json, pytest
import entparse

def test_list_container():
    val = [1.1, '2', [3]]
    parser = entparse.ParseOutput()
    parser.parse(json.dumps(val), True)
    assert val == parser.tolist(json.dumps(val))

def test_dict_container():
    # todo: make this list actually a list
    val = {'a':1, 'b':[1,2], 'c':"x"}
    parser = entparse.ParseOutput()
    parser.parse(json.dumps(val), True)
    assert val == parser.todict(json.dumps(val))

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
    assert res == map(ord, 'abbc')

    with pytest.raises(entparse.RerunError):
        citer = entparse.CharIterator('abc')
        for _ in citer:
            citer.rerun()
