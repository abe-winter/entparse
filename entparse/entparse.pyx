cimport entparse
import json

cdef enum ParserState:
    # note: post_comma and pre_comma can only appear directly above a dict_outer or list_outer
    post_comma
    begin_val
    top, dict_outer, list_outer, double_quote, single_quote, backslash, list_value, pre_float, post_float,
    dict_key, dict_sep
    not_set

def translate_parserstate(ParserState state):
    return {
        post_comma: 'post_comma',
        begin_val: 'begin_val',
        top: 'top',
        dict_outer: 'dict_outer',
        list_outer: 'list_outer',
        double_quote: 'double_quote',
        single_quote: 'single_quote',
        backslash: 'backslash',
        list_value: 'list_value',
        pre_float: 'pre_float',
        post_float: 'post_float',
        dict_key: 'dict_key',
        dict_sep: 'dict_sep',
    }[state]

# [ list_outer post_comma ]
# [ list_outer post_comma "a" pre_comma , post_comma ]

class EntparseError(StandardError): pass
class UnexpectedCase(EntparseError): pass
class IncompleteParse(EntparseError): pass
class IncompleteJson(EntparseError): pass
class IllegalChar(EntparseError): pass
class RerunError(EntparseError): pass
class OuterNotCollection(EntparseError): pass
class EmptyStack(EntparseError): pass
class FullStack(EntparseError): pass

cdef class Frame:
    ""
    cdef ParserState state
    cdef int startpos
    cdef int in_use

    def __cinit__(self):
        self.state = not_set
        self.startpos = 0
        self.in_use = 0

    cdef void set(self, ParserState state, int startpos):
        self.in_use = 1
        self.state = state
        self.startpos = startpos

    cdef void clear(self):
        self.in_use = 0

cdef class CharIterator:
    """wrapper for iterating through strings with the ability to rerun a character.
    reruns are limited to prevent infinite loops.
    """
    cdef unsigned int nextpos
    cdef unsigned int max_nextpos
    cdef unsigned int strlen
    cdef str string
    cdef unsigned int rerun_count
    cdef const char* buf

    def __cinit__(self, str string):
        self.nextpos = 0
        self.max_nextpos = 0 # for rerun
        self.string = string
        self.rerun_count = 0
        self.buf = self.string
        self.strlen = len(self.string)

    cpdef rerun(self):
        if self.rerun_count >= 1:
            raise RerunError('too many reruns', self.rerun_count)
        if self.nextpos == 0:
            raise RerunError("can't rerun initial")
        self.nextpos -= 1
        self.rerun_count += 1

    cdef int looping(self):
        return self.nextpos < self.strlen

    cdef char nextchar(self):
        self.nextpos += 1
        if self.nextpos > self.max_nextpos:
            self.max_nextpos = self.nextpos
            self.rerun_count = 0
        return self.buf[self.nextpos - 1]

    def __iter__(self):
        while self.looping():
            char_ = self.nextchar()
            yield self.nextpos - 1, char_

cdef class Stack:
    cdef unsigned int n
    cdef ParserState[20] stack

    def __cinit__(self):
        self.n = 0

    cdef ParserState peek(self):
        if self.n == 0:
            raise EmptyStack('peek')
        else:
            return self.stack[self.n - 1]

    cdef void push(self, ParserState state):
        if self.n >= 20:
            raise FullStack('push')
        else:
            self.stack[self.n] = state
            self.n += 1

    cdef void pop(self):
        if self.n > 0:
            self.n -= 1
        else:
            raise EmptyStack('pop')

    cdef replace(self, ParserState state):
        "replace stack-top element. shorthand for pop/push"
        if self.n == 0:
            raise EmptyStack('replace')
        self.stack[self.n - 1] = state

    def tolist(self):
        "this is slow; only use for debugging"
        return [translate_parserstate(self.stack[i]) for i in range(self.n)]

cdef int isspace(char c):
    return c == ' ' or c == '\t'

cdef int isdigit(char c):
    return c >= '0' and c <= '9'

cdef class JEBExtent:
    cdef public slice slice
    cdef public type type

    cdef void set_(self, slice slice, type type):
        self.slice = slice
        self.type = type

    def value(self, str orig_str):
        return orig_str[self.slice]

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

cdef class ExtentList:
    def __init__(self, width):
        self.n = 0
        self._extents = [JEBExtent() for i in range(width)]

    cdef clear(self):
        self.n = 0

    def __len__(self):
        return self.n

    @property
    def extents(self):
        return self._extents[:self.n]

    cdef push(self, slice slice, type type):
        # todo: type should be a ParserState
        cdef JEBExtent extent
        if self.n < len(self._extents):
            extent = self._extents[self.n]
            extent.set_(slice, type)
            self.n += 1
        elif self.n == len(self._extents):
            self._extents.append(JEBExtent())
            self.push(slice, type)
        else:
            raise UnexpectedCase("shouldn't be possible for n to get greater than len(extents)")

cdef class ParseOutput:
    """Stores result of parse.
    -- for a list input, keys is None
    -- for a dict input, keys is a list of JEBExtent for the keys
    For both, values is a list of JEBExtent representing the collection values.
    """

    def __init__(self, width=20):
        self.keys = ExtentList(width)
        self.values = ExtentList(width)

    def tolist(self, str string):
        "note: this succeeds even for dictionaries"
        print self.values.extents[:self.values.n]
        return [
            json.loads(v.value(string))
            for v in self.values.extents
        ]

    def todict(self, str string):
        if len(self.keys) != len(self.values):
            raise TypeError("todict() requires matched keys and values")
        return {
            k.value(string): json.loads(v.value(string))
            for k, v in zip(self.keys.extents, self.values.extents)
        }

    cdef clear(self):
        self.keys.clear()
        self.values.clear()

    cpdef void parse(self, str string, bint verbose):
        "takes a string representing a collection in json (list or dict). returns ParseOutput"
        # todo: replace this with a static-allocated stack and go dynamic only when needed (and the permit_malloc flag is False)
        cdef Stack stack = Stack()
        stack.push(top)
        stack.push(begin_val)
        cdef CharIterator citer = CharIterator(string)
        cdef Frame outer_frame = Frame()
        if verbose:
            print 'parsing %r' % string
        self.clear()
        cdef unsigned int i
        cdef char char_
        while citer.looping():
            # todo: generate this logic from a transition model that can be verified for properties
            char_ = citer.nextchar()
            i = citer.nextpos - 1
            if verbose:
                print i, chr(char_), stack.tolist()
            if not stack:
                raise UnexpectedCase("shouldn't get here -- we should reach top state first")
            state = stack.peek()
            if state == top:
                raise IncompleteParse(i, string[:i], string[i:])
            elif isspace(char_):
                pass
            elif state == begin_val:
                stack.pop()
                if char_ == '{':
                    stack.push(dict_outer)
                elif char_ == '[':
                    stack.push(list_outer)
                elif stack.n == 1 and stack.peek() == top:
                    raise OuterNotCollection(i, char_)
                elif char_ == '"':
                    stack.push(double_quote)
                elif char_ == "'":
                    stack.push(single_quote)
                elif isdigit(char_):
                    stack.push(pre_float)
                else:
                    raise IllegalChar("bad first character for begin_val", i, char_)
                if stack.n == 3:
                    if outer_frame.in_use:
                        raise UnexpectedCase("reusing outer_frame before clearing it")
                    outer_frame.set(stack.peek(), i)
            elif state == list_outer:
                if stack.n == 2 and outer_frame.in_use:
                    self.values.push(
                        slice(outer_frame.startpos, i),
                        JEBExtent.enum2type(outer_frame.state),
                    )
                    outer_frame.clear()
                if char_ == ']':
                    stack.pop()
                elif char_ == ',':
                    stack.push(begin_val)
                else:
                    stack.push(begin_val)
                    citer.rerun()
                    # todo: only allow this clause in list_beginning case
                    # raise IllegalChar("unexpected char at list scope", i, char_)
            elif state == dict_outer:
                if stack.n == 2 and outer_frame.in_use:
                    # todo: merge this with identical clause in list_outer
                    self.values.push(
                        slice(outer_frame.startpos, i),
                        JEBExtent.enum2type(outer_frame.state),
                    )
                    outer_frame.clear()
                if char_ == '}':
                    stack.pop()
                elif char_ == '"':
                    stack.push(dict_key)
                    if stack.n == 3:
                        if outer_frame.in_use:
                            raise UnexpectedCase("reusing outer_frame before clear (in dict_key)")
                        outer_frame.set(stack.peek(), i+1)
                elif char_ == ',':
                    # todo: distinguish between expecting a dict key vs comma
                    pass
                else:
                    raise IllegalChar("expected key or , at dict_outer scope", i, char_)
            elif state in (double_quote, dict_key):
                if char_ == '\\':
                    stack.push(backslash)
                elif char_ == '"':
                    stack.pop()
                    if state == dict_key:
                        if stack.n == 2 and outer_frame.in_use:
                            self.keys.push(
                                slice(outer_frame.startpos, i),
                                JEBExtent.enum2type(outer_frame.state),
                            )
                            outer_frame.clear()
                        stack.push(dict_sep)
                else:
                    pass
            elif state == single_quote:
                raise NotImplementedError
            elif state == backslash:
                raise NotImplementedError
            elif state == dict_sep:
                if char_ == ':':
                    stack.replace(begin_val)
                else:
                    raise IllegalChar("expected ':' after key in dict scope", i, char_)
            elif state == pre_float:
                if isdigit(char_):
                    pass
                elif char_ == '.':
                    stack.replace(post_float)
                else:
                    stack.pop()
                    citer.rerun()
            elif state == post_float:
                if isdigit(char_):
                    pass
                else:
                    stack.pop()
                    citer.rerun()
            else:
                raise UnexpectedCase("unk ParserState value", state)
        if stack.n != 1 or stack.peek() != top:
            raise IncompleteJson

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
