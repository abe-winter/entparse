import json

cdef enum ParserState:
    # note: post_comma and pre_comma can only appear directly above a dict_outer or list_outer
    pre_comma, post_comma
    begin_val
    top, dict_outer, list_outer, double_quote, single_quote, backslash, list_value, pre_float, post_float,
    dict_key, dict_sep

# [ list_outer post_comma ]
# [ list_outer post_comma "a" pre_comma , post_comma ]

class EntparseError(StandardError): pass
class UnexpectedCase(EntparseError): pass
class IncompleteParse(EntparseError): pass
class IncompleteJson(EntparseError): pass
class IllegalChar(EntparseError): pass
class RerunError(EntparseError): pass
class OuterNotCollection(EntparseError): pass

cdef class Frame:
    ""
    cdef ParserState state
    cdef int startpos

    def __cinit__(self, ParserState state, int startpos):
        self.state = state
        self.startpos = startpos

cdef class ParseOutput:
    """Stores result of parse.
    -- for a list input, keys is None
    -- for a dict input, keys is a list of JEBExtent for the keys
    For both, values is a list of JEBExtent representing the collection values.
    """
    cdef public list keys
    cdef public list values

    def __cinit__(self):
        self.keys = []
        self.values = []

    def tolist(self):
        "note: this succeeds even for dictionaries"
        return [
            json.loads(v.value())
            for v in self.values
        ]

    def todict(self):
        if len(self.keys) != len(self.values):
            raise TypeError("todict() requires matched keys and values")
        return {
            k.value(): json.loads(v.value())
            for k, v in zip(self.keys, self.values)
        }

cdef class CharIterator:
    """wrapper for iterating through strings with the ability to rerun a character.
    reruns are limited to prevent infinite loops.
    """
    cdef int pos
    cdef str string
    cdef bint rerun_next
    cdef unsigned int rerun_count

    def __cinit__(self, str string):
        self.pos = -1
        self.string = string
        self.rerun_next = False
        self.rerun_count = 0

    def rerun(self, ):
        if self.rerun_count >= 1:
            raise RerunError('too many reruns', self.rerun_count)
        self.rerun_next = True
        self.rerun_count += 1

    def __iter__(self):
        while 1:
            if self.rerun_next:
                if self.pos < 0:
                    raise UnexpectedCase("rerun in initial position")
                self.rerun_next = False
            else:
                self.pos += 1
                self.rerun_count = 0
            if self.pos >= len(self.string):
                break
            else:
                yield self.pos, self.string[self.pos]

cdef class JEBExtent:
    cdef public slice slice
    cdef public type type
    cdef public str orig_str

    def __cinit__(self, slice slice, type type, str orig_str):
        self.slice = slice
        self.type = type
        self.orig_str = orig_str

    def value(self):
        return self.orig_str[self.slice]

    @staticmethod
    def enum2type(ParserState state):
        if state == dict_outer:
            return dict
        elif state == list_outer:
            return list
        elif state in (double_quote, single_quote, dict_key):
            return str
        elif state in (pre_float, post_float):
            # note: I don't think post_float can get here
            return float
        else:
            raise TypeError("no type translation for ParserState", state)

    @classmethod
    def parse(type class_, str string, bint verbose=False):
        "takes a string representing a collection in json (list or dict). returns ParseOutput"
        # todo: replace this with a static-allocated stack and go dynamic only when needed (and the permit_malloc flag is False)
        cdef list stack = [top, begin_val]
        output = ParseOutput()
        citer = CharIterator(string)
        cdef Frame outer_frame = None
        if verbose:
            print 'parsing %r' % string
        for i, char_ in citer:
            if verbose:
                print i, char_, stack
            if not stack:
                raise UnexpectedCase("shouldn't get here -- we should reach top state first")
            state = stack[-1]
            if state == top:
                raise IncompleteParse(i, string[:i], string[i:])
            elif char_.isspace():
                pass
            elif state == begin_val:
                stack.pop()
                if char_ == '{':
                    stack.append(dict_outer)
                elif char_ == '[':
                    stack.append(list_outer)
                elif stack == [top]:
                    raise OuterNotCollection(i, char_)
                elif char_ == '"':
                    stack.append(double_quote)
                elif char_ == "'":
                    stack.append(single_quote)
                elif char_.isdigit():
                    stack.append(pre_float)
                else:
                    raise IllegalChar("bad first character for begin_val", i, char_)
                if len(stack) == 3:
                    if outer_frame is not None:
                        raise UnexpectedCase("reusing outer_frame before clearing it")
                    outer_frame = Frame(stack[-1], i)
            elif state == list_outer:
                if len(stack) == 2 and outer_frame:
                    output.values.append(JEBExtent(
                        slice(outer_frame.startpos, i),
                        JEBExtent.enum2type(outer_frame.state),
                        string
                    ))
                    outer_frame = None
                if char_ == ']':
                    stack.pop()
                elif char_ == ',':
                    stack.append(begin_val)
                else:
                    stack.append(begin_val)
                    citer.rerun()
                    # todo: only allow this clause in list_beginning case
                    # raise IllegalChar("unexpected char at list scope", i, char_)
            elif state == dict_outer:
                if len(stack) == 2 and outer_frame:
                    # todo: merge this with identical clause in list_outer
                    output.values.append(JEBExtent(
                        slice(outer_frame.startpos, i),
                        JEBExtent.enum2type(outer_frame.state),
                        string
                    ))
                    outer_frame = None
                if char_ == '}':
                    stack.pop()
                elif char_ == '"':
                    stack.append(dict_key)
                    if len(stack) == 3:
                        if outer_frame is not None:
                            raise UnexpectedCase("reusing outer_frame before clear (in dict_key)")
                        outer_frame = Frame(stack[-1], i+1)
                elif char_ == ',':
                    # todo: distinguish between expecting a dict key vs comma
                    pass
                else:
                    raise IllegalChar("expected key or , at dict_outer scope", i, char_)
            elif state == pre_comma:
                raise NotImplementedError
            elif state in (double_quote, dict_key):
                if char_ == '\\':
                    stack.append(backslash)
                elif char_ == '"':
                    stack.pop()
                    if state == dict_key:
                        if len(stack) == 2 and outer_frame:
                            output.keys.append(JEBExtent(
                                slice(outer_frame.startpos, i),
                                JEBExtent.enum2type(outer_frame.state),
                                string
                            ))
                            outer_frame = None
                        stack.append(dict_sep)
                else:
                    pass
            elif state == single_quote:
                raise NotImplementedError
            elif state == backslash:
                raise NotImplementedError
            elif state == dict_sep:
                if char_ == ':':
                    stack[-1] = begin_val
                else:
                    raise IllegalChar("expected ':' after key in dict scope", i, char_)
            elif state == list_value:
                # todo(delete): (never set)
                if char_ == ']':
                    stack.pop()
                    citer.rerun()
                elif char_.isspace():
                    pass
                else:
                    # todo: below here should rerun as value-start
                    raise NotImplementedError
            elif state == pre_float:
                if char_.isdigit():
                    pass
                elif char_ == '.':
                    stack[-1] = post_float
                else:
                    stack.pop()
                    citer.rerun()
            elif state == post_float:
                if char_.isdigit():
                    pass
                else:
                    stack.pop()
                    citer.rerun()
            else:
                raise UnexpectedCase("unk ParserState value", state)
        if stack != [top]:
            raise IncompleteJson
        return output

cdef class JEBEntity:
    "base for entity types"

cdef class JEBList(JEBEntity):
    cdef public int maxwidth

    def __getitem__(self, unsigned int index):
        raise NotImplementedError

cdef class JEBDict(JEBEntity):
    cdef public list fields

    def __getitem__(self, basestring key):
        raise NotImplementedError
