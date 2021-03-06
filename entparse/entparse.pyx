from libc.stdlib cimport malloc, free
import json
cimport entparse

cdef enum FastError:
    no_error
    error

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

class EntparseError(StandardError): pass
class UnexpectedCase(EntparseError): pass
class IncompleteParse(EntparseError): pass
class IncompleteJson(EntparseError): pass
class IllegalChar(EntparseError): pass
class RerunError(EntparseError): pass
class OuterNotCollection(EntparseError): pass
class EmptyStack(EntparseError): pass
class FullStack(EntparseError): pass
class AlreadyFreed(EntparseError): pass
class FastErrorException(EntparseError): pass

cdef struct Frame:
    ParserState state
    int startpos
    int in_use

cdef frame_init(Frame* self):
    self.state = not_set
    self.startpos = 0
    self.in_use = 0

cdef void frame_set(Frame* self, ParserState state, int startpos):
    self.in_use = 1
    self.state = state
    self.startpos = startpos

cdef void frame_clear(Frame* self):
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
        # todo: next hotspot for speedup is CharIterator; make this a struct.
        #   Also look into skipping reference-dupe for the string. Are we in nogil?
        self.nextpos = 0
        self.max_nextpos = 0 # for rerun
        self.string = string
        self.rerun_count = 0
        self.buf = self.string
        self.strlen = len(self.string)

    def rerun(self):
        if self.rerun_count >= 1:
            raise RerunError('too many reruns', self.rerun_count)
        if self.nextpos == 0:
            raise RerunError("can't rerun initial")
        self.c_rerun()
    
    cdef FastError c_rerun(self):
        if self.rerun_count >= 1:
            return error # too many reruns
        if self.nextpos == 0:
            return error # can't rerun initial
        self.nextpos -= 1
        self.rerun_count += 1
        return no_error

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

cdef struct Stack:
    unsigned int n
    # todo: make this mallocable and resizable; scope it with ParseOutput
    ParserState[20] stack

cdef void stack_init(Stack* self):
    self.n = 0

cdef ParserState stack_peek(Stack* self):
    "only call this after checking empty stack"
    return self.stack[self.n - 1]

cdef void stack_push(Stack* self, ParserState state):
    if self.n >= 20:
        raise FullStack('push')
    else:
        self.stack[self.n] = state
        self.n += 1

cdef void stack_pop(Stack* self):
    if self.n > 0:
        self.n -= 1
    else:
        raise EmptyStack('pop')

cdef void stack_replace(Stack* self, ParserState state):
    "replace stack-top element. shorthand for pop/push"
    if self.n == 0:
        raise EmptyStack('replace')
    self.stack[self.n - 1] = state

cdef stack_tolist(Stack* self):
    "this is slow; only use for debugging"
    return [translate_parserstate(self.stack[i]) for i in range(self.n)]

cdef int isspace(char c):
    return c == ' ' or c == '\t'

cdef int isdigit(char c):
    return c >= '0' and c <= '9'

cdef object enum2type(ParserState state):
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
    def __init__(self, unsigned int width):
        self.n = 0
        self.width = width
        self._extents = <JEBExtent*>malloc(sizeof(JEBExtent) * width)

    def __dealloc__(self):
        free(self._extents)
        self._extents = NULL


    cdef void clear(self):
        self.n = 0

    def __len__(self):
        return self.n

    @property
    def extents(self):
        if self._extents == NULL:
            raise AlreadyFreed
        else:
            return [self._extents[i] for i in range(self.n)]

    cdef void set(self, unsigned int i, unsigned int a, unsigned int b, ParserState state):
        cdef JEBExtent* extent = &self._extents[i]
        extent.a = a
        extent.b = b
        extent.type = state

    cdef void push(self, unsigned int a, unsigned int b, ParserState state):
        if self.n < self.width:
            self.set(self.n, a, b, state)
            self.n += 1
        else:
            raise NotImplementedError('realloc in ExtentList')

def extent_slice(JEBExtent extent, str orig_str):
    return orig_str[extent.a:extent.b]

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
        return [
            json.loads(extent_slice(v, string))
            for v in self.values.extents
        ]

    def todict(self, str string):
        if len(self.keys) != len(self.values):
            raise TypeError("todict() requires matched keys and values")
        return {
            extent_slice(k, string): json.loads(extent_slice(v, string))
            for k, v in zip(self.keys.extents, self.values.extents)
        }

    cdef void clear(self):
        self.keys.clear()
        self.values.clear()

    cpdef void parse(self, str string, bint verbose):
        "takes a string representing a collection in json (list or dict). returns ParseOutput"
        # todo: replace this with a static-allocated stack and go dynamic only when needed (and the permit_malloc flag is False)
        cdef Stack stack
        stack_init(&stack)
        stack_push(&stack, top)
        stack_push(&stack, begin_val)
        cdef CharIterator citer = CharIterator(string)
        cdef Frame outer_frame
        frame_init(&outer_frame)
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
                print i, chr(char_), stack_tolist(&stack), outer_frame
            if not stack.n:
                raise UnexpectedCase("shouldn't get here -- we should reach top state first")
            state = stack_peek(&stack)
            if state == top:
                raise IncompleteParse(i, string[:i], string[i:])
            elif isspace(char_):
                pass
            elif state == begin_val:
                stack_pop(&stack)
                if char_ == '{':
                    stack_push(&stack, dict_outer)
                elif char_ == '[':
                    stack_push(&stack, list_outer)
                elif stack.n == 1 and stack_peek(&stack) == top:
                    raise OuterNotCollection(i, char_)
                elif char_ == '"':
                    stack_push(&stack, double_quote)
                elif char_ == "'":
                    stack_push(&stack, single_quote)
                elif isdigit(char_):
                    stack_push(&stack, pre_float)
                else:
                    raise IllegalChar("bad first character for begin_val", i, char_)
                if stack.n == 3:
                    if outer_frame.in_use:
                        raise UnexpectedCase("reusing outer_frame before clearing it")
                    # todo: check stack.n before stack.peek
                    frame_set(&outer_frame, stack_peek(&stack), i)
            elif state == list_outer:
                if stack.n == 2 and outer_frame.in_use:
                    self.values.push(outer_frame.startpos, i, outer_frame.state)
                    frame_clear(&outer_frame)
                if char_ == ']':
                    stack_pop(&stack)
                elif char_ == ',':
                    stack_push(&stack, begin_val)
                else:
                    stack_push(&stack, begin_val)
                    if citer.c_rerun() != no_error:
                        raise FastErrorException('rerun')
                    # todo: only allow this clause in list_beginning case
                    # raise IllegalChar("unexpected char at list scope", i, char_)
            elif state == dict_outer:
                if stack.n == 2 and outer_frame.in_use:
                    # todo: merge this with identical clause in list_outer
                    self.values.push(outer_frame.startpos, i, outer_frame.state)
                    frame_clear(&outer_frame)
                if char_ == '}':
                    stack_pop(&stack)
                elif char_ == '"':
                    stack_push(&stack, dict_key)
                    if stack.n == 3:
                        if outer_frame.in_use:
                            raise UnexpectedCase("reusing outer_frame before clear (in dict_key)")
                        # todo: check 
                        frame_set(&outer_frame, stack_peek(&stack), i+1)
                elif char_ == ',':
                    # todo: distinguish between expecting a dict key vs comma
                    pass
                else:
                    raise IllegalChar("expected key or , at dict_outer scope", i, char_)
            elif state in (double_quote, dict_key):
                if char_ == '\\':
                    stack_push(&stack, backslash)
                elif char_ == '"':
                    stack_pop(&stack)
                    if state == dict_key:
                        if stack.n == 2 and outer_frame.in_use:
                            self.keys.push(outer_frame.startpos, i, outer_frame.state)
                            frame_clear(&outer_frame)
                        stack_push(&stack, dict_sep)
                else:
                    pass
            elif state == single_quote:
                raise NotImplementedError
            elif state == backslash:
                raise NotImplementedError
            elif state == dict_sep:
                if char_ == ':':
                    stack_replace(&stack, begin_val)
                else:
                    raise IllegalChar("expected ':' after key in dict scope", i, char_)
            elif state == pre_float:
                if isdigit(char_):
                    pass
                elif char_ == '.':
                    stack_replace(&stack, post_float)
                else:
                    stack_pop(&stack)
                    if citer.c_rerun() == error:
                        raise FastErrorException('rerun')
            elif state == post_float:
                if isdigit(char_):
                    pass
                else:
                    stack_pop(&stack)
                    if citer.c_rerun() == error:
                        raise FastErrorException('rerun')
            else:
                raise UnexpectedCase("unk ParserState value", state)
        if stack.n != 1 or stack_peek(&stack) != top:
            raise IncompleteJson
