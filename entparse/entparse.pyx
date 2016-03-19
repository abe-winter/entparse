cdef enum ParserState:
    top, dict_outer, list_outer, double_quote, single_quote, backslash, dict_key, dict_value, list_value, pre_float, post_float

cdef enum NextParse:
    continue_, rerun_

class EntparseError(StandardError): pass
class UnexpectedCase(EntparseError): pass
class IncompleteParse(EntparseError): pass
class IncompleteJson(EntparseError): pass
class IllegalChar(EntparseError): pass
class RerunError(EntparseError): pass

cdef class ParseOutput:
    """Stores result of parse.
    -- for a list input, keys is None
    -- for a dict input, keys is a list of JEBExtent for the keys
    For both, values is a list of JEBExtent representing the collection values.
    """
    cdef list keys
    cdef list values

cdef parse(list stack, int i, char char_, str string, ParseOutput output):
    raise NotImplementedError

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

    @classmethod
    def parse(type class_, str string):
        """takes a string representing a collection in json (list or dict).
        returns (keys, values) where:
            
        """
        # todo: replace this with a static-allocated stack and go dynamic only when needed (and the permit_malloc flag is False)
        cdef list stack = [top]
        for i, char_ in enumerate(string):
            if not stack:
                raise UnexpectedCase("shouldn't get here -- we should reach top state first")
            state = stack[-1]
            if state == top and i != 0:
                raise IncompleteParse(i, string[:i], string[i:])
            elif state == top:
                if char_ == '{':
                    stack.append(dict_outer)
                    continue
                elif char_ == '[':
                    stack.append(list_outer)
                    continue
                else:
                    raise IllegalChar("first character must be '[' or '{'")
            elif state == dict_outer:
                raise NotImplementedError
            elif state == list_outer:
                #
                raise NotImplementedError
            elif state == double_quote:
                raise NotImplementedError
            elif state == single_quote:
                raise NotImplementedError
            elif state == backslash:
                raise NotImplementedError
            elif state == dict_key:
                raise NotImplementedError
            elif state == dict_value:
                raise NotImplementedError
            elif state == list_value:
                if char_ == ']':
                    stack.pop()
                    if stack[-1] != list_outer:
                        raise UnexpectedCase("list_value not adjacent to list_outer", stack[-1])
                    # todo: make this a rerun case
                    stack.pop()
                    continue
                elif char_.isspace():
                    continue
                else:
                    # todo: below here should rerun as value-start
                    raise NotImplementedError
            elif state == pre_float:
                raise NotImplementedError
            elif state == post_float:
                raise NotImplementedError
            else:
                raise UnexpectedCase("unk ParserState value", state)
        if stack != [top]:
            raise IncompleteJson
        raise NotImplementedError

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
