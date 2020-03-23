import logging
import sqlite3

import re
import ply.lex as lex
import ply.yacc as yacc
from ply.lex import LexError, TOKEN

logger = logging.getLogger(__name__)
#logger.addHandler(logging.NullHandler())

# assemble catchall regexp
p21_real = r'(?:[+-]*[0-9][0-9]*\.[0-9]*(?:E[+-]*[0-9][0-9]*)?)'
p21_integer = r'(?:[+-]*[0-9][0-9]*)'
p21_string = r"(?:'(?:[][!\"*$%&.#+,\-()?/:;<=>@{}|^`~0-9a-zA-Z_\\ ]|'')*')"
p21_binary = r'(?:"[0-3][0-9A-F]*")'
p21_enumeration = r'(?:\.[A-Z_][A-Z0-9_]*\.)'
p21_keyword = r'(?:!|)[A-Za-z_][0-9A-Za-z_]*'
p21_eid = r'\#[0-9]+'
p21_literals = r'(?:[(),*$])'
_types = [p21_real, p21_integer, p21_string, p21_binary, p21_enumeration,
          p21_keyword, p21_eid, p21_literals]
catchall_re = '(?:' + '|'.join(_types) + ')+'

base_tokens = ['PART21_START', 'PART21_END', 'HEADER', 'DATA', 'ENDSEC',
               'INTEGER', 'REAL', 'KEYWORD', 'STRING', 'BINARY', 'ENUMERATION',
               'EID', 'RAW']

####################################################################################################
# Lexer 
####################################################################################################
class Lexer(object):
    tokens = list(base_tokens)
    literals = '()=;,*$'

    # TODO: this can probably be done with less states
    states = (('slurp', 'exclusive'),
              ('header', 'exclusive'),
              ('dataparams', 'exclusive'),
              ('data', 'exclusive'),
              ('raw', 'exclusive'),
              ('params', 'exclusive'))

    def __init__(self, debug=0, optimize=0, header_limit=4096):
        self.base_tokens = list(base_tokens)
        self.schema_dict = {}
        self.active_schema = {}
        self.input_length = 0
        self.header_limit = header_limit
        self.lexer = lex.lex(module=self, debug=debug, debuglog=logger, optimize=optimize,
                             errorlog=logger)
        self.reset()

    def __getattr__(self, name):
        if name == 'lineno':
            return self.lexer.lineno
        elif name == 'lexpos':
            return self.lexer.lexpos
        else:
            raise AttributeError

    def input(self, s):
        self.lexer.input(s)
        self.input_length += len(s)

    def reset(self):
        self.lexer.lineno = 1
        self.lexer.lvl = 0
        self.lexer.begin('slurp')
        
    def token(self):
        try:
            return next(self.lexer)
        except StopIteration:
            return None

    def activate_schema(self, schema_name):
        if schema_name in self.schema_dict:
            self.active_schema = self.schema_dict[schema_name]
        else:
            raise ValueError('schema not registered')

    def register_schema(self, schema_name, entities):
        if schema_name in self.schema_dict:
            raise ValueError('schema already registered')

        for k in entities:
            if k in self.base_tokens: raise ValueError('schema cannot override base_tokens')
        
        if isinstance(entities, list):
            entities = dict((k, k) for k in entities)

        self.schema_dict[schema_name] = entities

    def t_slurp_error(self, t):
        m = re.search(r'(?P<comment>/\*)|(ISO-10303-21;)', t.value[:self.header_limit])
        if m:
            if m.group('comment'):
                t.lexer.skip(m.start())
            else:
                t.type = 'PART21_START'
                t.value = m.group()
                t.lexpos += m.start()
                t.lineno += t.value[:m.start()].count('\n')
                t.lexer.lexpos += m.end()
                t.lexer.begin('INITIAL')
                return t
        elif len(t.value) < self.header_limit:
            t.lexer.skip(len(t.value))
        else:
            raise LexError("Scanning error. try increasing lexer header_limit parameter",
                           "{0}...".format(t.value[0:20]))
            

    def t_ANY_COMMENT(self, t):
        r'/\*(?:.|\n)*?\*/'
        t.lexer.lineno += t.value.count('\n')


    def t_PART21_END(self, t):
        r'END-ISO-10303-21;'
        self.lexer.lvl = 0
        self.lexer.begin('slurp')        
        return t
    def t_HEADER(self, t):
        r'HEADER;'
        t.lexer.push_state('header')
        return t
    def t_header_data_ENDSEC(self, t):
        r'ENDSEC;'
        t.lexer.pop_state()
        return t
    def t_DATA(self, t):
        r'DATA\b'
        t.lexer.push_state('dataparams')
        return t


    @TOKEN(p21_keyword)
    def t_header_KEYWORD(self, t):
        return t
    def t_dataparams_header_lparens(self, t):
        r'\('
        t.type = '('
        t.lexer.lvl += 1
        t.lexer.push_state('params')
        return t
    def t_dataparams_semi(self, t):
        r';'
        t.type = ';'
        t.lexer.pop_state()
        t.lexer.push_state('data')
        return t


    @TOKEN(p21_integer)
    def t_params_INTEGER(self, t):
        return t
    @TOKEN(p21_real)
    def t_params_REAL(self, t):
        return t
    @TOKEN(p21_keyword)
    def t_params_KEYWORD(self, t):
        return t
    @TOKEN(p21_string)
    def t_params_STRING(self, t):
        return t
    @TOKEN(p21_binary)
    def t_params_BINARY(self, t):
        return t
    @TOKEN(p21_enumeration)
    def t_params_ENUMERATION(self, t):
        return t
    @TOKEN(p21_eid)
    def t_params_EID(self, t):
        return t
    def t_params_lparens(self, t):
        r'\('
        t.type = '('
        t.lexer.lvl += 1
        return t
    def t_params_rparens(self, t):
        r'\)'
        t.type = ')'
        t.lexer.lvl -= 1
        if t.lexer.lvl == 0:
            t.lexer.pop_state()
        return t


    @TOKEN(p21_eid)
    def t_data_EID(self, t):
        return t
    @TOKEN(p21_keyword)
    def t_data_KEYWORD(self, t):
        t.lexer.push_state('raw')
        return t
    def t_data_lparens(self, t):
        r'\('
        t.lexer.lexpos -= 1
        t.lexer.push_state('raw')

    @TOKEN(catchall_re)
    def t_raw_RAW(self, t):
        return t
    def t_raw_end(self, t):
        r';'
        t.lexer.pop_state()
        t.type = ';'
        return t

    def t_ANY_newline(self, t):
        r'\n+'
        t.lexer.lineno += len(t.value)    
    t_ANY_ignore = ' \t\r'


####################################################################################################
# Simple Model
####################################################################################################
class P21File:
    def __init__(self, header, *sections):
        self.header = header
        self.sections = list(*sections)

class P21Header:
    def __init__(self, file_description, file_name, file_schema):
        self.file_description = file_description
        self.file_name = file_name
        self.file_schema = file_schema
        self.extra_headers = []

class HeaderEntity:
    def __init__(self, type_name, *params):
        self.type_name = type_name
        self.params = list(params) if params else []

class Section:
    def __init__(self, entities):
        self.entities = entities

class SimpleEntity:
    def __init__(self, ref, type_name, *params):
        self.ref = ref
        self.type_name = type_name
        self.params = list(params) if params else []

class ComplexEntity:
    def __init__(self, ref, *params):
        self.ref = ref
        self.params = list(params) if params else []

class TypedParameter:
    def __init__(self, type_name, *params):
        self.type_name = type_name
        self.params = list(params) if params else None


####################################################################################################
# Parser
####################################################################################################
class Parser(object):
    tokens = list(base_tokens)
    start = 'exchange_file'
    
    def __init__(self, lexer=None, debug=0):
        self.lexer = lexer if lexer else Lexer()

        try: self.tokens = lexer.tokens
        except AttributeError: pass

        self.parser = yacc.yacc(module=self, debug=debug, debuglog=logger, errorlog=logger)
        self.reset()
    
    def parse(self, p21_data, **kwargs):
        #TODO: will probably need to change this function if the lexer is ever to support t_eof
        self.lexer.reset()
        self.lexer.input(p21_data)

        if 'debug' in kwargs:
            result = self.parser.parse(lexer=self.lexer, debug=logger,
                                       ** dict((k, v) for k, v in kwargs.items() if k != 'debug'))
        else:
            result = self.parser.parse(lexer=self.lexer, **kwargs)
        return result

    def reset(self):
        self.closedb()
        self.initdb()
        
    def p_exchange_file(self, p):
        """exchange_file : PART21_START header_section data_section_list PART21_END"""
        p[0] = P21File(p[2], p[3])

    def p_header_section(self, p):
        """header_section : HEADER header_entity header_entity header_entity ENDSEC"""
        p[0] = P21Header(p[2], p[3], p[4])

    def p_header_section_with_entity_list(self, p):
        """header_section : HEADER header_entity header_entity header_entity header_entity_list ENDSEC"""
        p[0] = P21Header(p[2], p[3], p[4])
        p[0].extra_headers = p[5]

    def p_header_entity(self, p):
        """header_entity : KEYWORD '(' parameter_list ')' ';'"""
        p[0] = HeaderEntity(p[1], p[3])

    def p_header_entity_list_init(self, p):
        """header_entity_list : header_entity"""
        p[0] = [p[1],]
        
    def p_header_entity_list(self, p):
        """header_entity_list : header_entity_list header_entity"""
        p[0] = p[1]
        p[0].append(p[2])

    def p_data_section(self, p):
        """data_section : data_start entity_instance_list ENDSEC""" 
        p[0] = Section(p[2])

    def p_data_start(self, p):
        """data_start : DATA '(' parameter_list ')' ';'"""
        pass

    def p_data_start_empty(self, p):
        """data_start : DATA '(' ')' ';'
                      | DATA ';'"""
        pass

    def p_data_section_list_init(self, p):
        """data_section_list : data_section"""
        p[0] = [p[1],]
        
    def p_data_section_list(self, p):
        """data_section_list : data_section_list data_section"""
        p[0] = p[1]
        p[0].append(p[2])

    def p_entity_instance_list_init(self, p):
        """entity_instance_list : entity_instance"""
        p[0] = [p[1],]
        
    def p_entity_instance_list(self, p):
        """entity_instance_list : entity_instance_list entity_instance"""
        p[0] = p[1] 
        p[0].append(p[2])

    def p_entity_instance(self, p):
        """entity_instance : simple_entity_instance
                           | complex_entity_instance"""
        p[0] = p[1]
        
    def p_entity_instance_error(self, p):
        """entity_instance  : EID '=' error ';'"""
        logger.error('resyncing parser, check input between lineno %d and %d', p.lineno(2), p.lineno(4))

    def p_simple_entity_instance(self, p):
        """simple_entity_instance : EID '=' KEYWORD raw_data ';'"""
        tmpl = "INSERT INTO data_table(id, type_name, raw_data, lineno) VALUES (?,?,?,?)"
        self.db_writer.execute(tmpl, (p[1], p[3], p[5], p.lineno(1)))

    def p_complex_entity_instance(self, p):
        """complex_entity_instance : EID '=' raw_data ';'"""
        tmpl = "INSERT INTO data_table VALUES (?,NULL,?,?,?)"
        self.db_writer.execute(tmpl, (p[1], p[4], p.lineno(1), 'C'))

    def p_raw_concat(self, p):
        """raw_data : raw_data RAW
                    | RAW"""
        try: p[0] = p[1] + p[2]
        except IndexError: p[0] = p[1]

    def p_parameter_list_init(self, p):
        """parameter_list : parameter"""
        p[0] = [p[1],]
        
    def p_parameter_list(self, p):
        """parameter_list : parameter_list ',' parameter"""
        p[0] = p[1]
        p[0].append(p[3])
        
    def p_parameter_simple(self, p):
        """parameter : STRING
                     | INTEGER
                     | REAL
                     | EID
                     | ENUMERATION
                     | BINARY
                     | '*'
                     | '$'
                     | typed_parameter
                     | list_parameter"""
        p[0] = p[1]

    def p_list_parameter(self, p):
        """list_parameter : '(' parameter_list ')'"""
        p[0] = p[2]

    def p_typed_parameter(self, p):
        """typed_parameter : KEYWORD '(' parameter ')'"""
        p[0] = TypedParameter(p[1], p[3])

    def p_parameter_empty_list(self, p):
        """parameter : '(' ')'"""
        p[0] = []

    def initdb(self):
        # TODO: memory or temp file
        self.db_cxn = sqlite3.connect(":memory:")
        self.db_writer = self.db_cxn.cursor()
        self.db_writer.executescript("""
            PRAGMA foreign_keys = ON;
            CREATE TABLE entity_enum (type TEXT(1) PRIMARY KEY);
            INSERT INTO entity_enum (rowid, type) VALUES (1, 'S'), (2, 'C');
            
            CREATE TABLE data_table (
                id TEXT PRIMARY KEY,
                type_name TEXT COLLATE NOCASE,
                raw_data TEXT NOT NULL,
                lineno INTEGER NOT NULL,
                entity_type TEXT(1) NOT NULL DEFAULT ('S') REFERENCES entity_enum(type)
            ) WITHOUT ROWID;
            
            CREATE INDEX ix_type_name ON data_table(type_name);
            CREATE INDEX ix_entity_type ON data_table(entity_type);
        """)
        self.db_cxn.commit()
        
    def closedb(self):
        try:
            self.db_cxn.commit()
            self.db_cxn.close()
        except AttributeError:
            pass
            

def debug_lexer():
    import codecs
    from os.path import normpath, expanduser
    
    logging.basicConfig()
    logger.setLevel(logging.DEBUG)
    
    lexer = Lexer(debug=True)
    
    p = normpath(expanduser('~/projects/src/stepcode/data/ap214e3/s1-c5-214/s1-c5-214.stp'))
    #p = normpath(expanduser('~/projects/src/stepcode/data/ap209/ATS7-out.stp'))
    with codecs.open(p, 'r', encoding='iso-8859-1') as f:
        s = f.read()
        lexer.input(s)
        while True:
            tok = lexer.token()
            if not tok: break
            print(tok)

def debug_parser():
    import codecs
    from os.path import normpath, expanduser

    logging.basicConfig()
    logger.setLevel(logging.DEBUG)

    parser = Parser()
    parser.reset()
    
    logger.info("***** parser debug *****")
    p = normpath(expanduser('~/projects/src/stepcode/data/ap214e3/s1-c5-214/s1-c5-214.stp'))
    with codecs.open(p, 'r', encoding='iso-8859-1') as f:
        s = f.read()
        try:
            parser.parse(s, debug=1)
        except SystemExit:
            pass
        
    logger.info("***** finished *****")
    
def test2():
    import os, os.path
    
    logging.basicConfig()
    logger.setLevel(logging.INFO)

    #lexer = lex.lex(optimize=1)
    #parser = yacc.yacc(optimize=1)
    lexer = lex.lex()
    parser = yacc.yacc()

    def parse_check(p):
        logger.info("processing {0}".format(p))
        with open(p, 'r', encoding='iso-8859-1') as f:
            s = f.read()
            lexer.input(s)
            lexer.lvl = 0
            parser.writer_cur = tempdb()
            parser.parse(lexer=lexer)

    logger.info("***** standard test *****")
    compat_list = []
    for d, _, files in os.walk(os.path.expanduser('~/projects/src/stepcode')):
        for f in filter(lambda x: x.endswith('.stp') or x.endswith('.p21'), files):
            p = os.path.join(d, f)
            try:
                parse_check(p)
            except LexError:
                logger.exception('Lexer issue, adding {0} to compatibility test list'.format(os.path.basename(p)))
                compat_list.append(p)

    logger.info("***** finished *****")

def test():
    import os, codecs
    from os.path import normpath, expanduser
    
    logging.basicConfig()
    logger.setLevel(logging.INFO)

    parser = Parser()

    def parse_check(p):
        logger.info("processing {0}".format(p))
        parser.reset()
        with codecs.open(p, 'r', encoding='iso-8859-1') as f:
            s = f.read()
            parser.parse(s)

    logger.info("***** standard test *****")
    stepcode_dir = normpath(os.path.expanduser('~/projects/src/stepcode'))
    for d, _, files in os.walk(stepcode_dir):
        for f in filter(lambda x: x.endswith('.stp'), files):
            p = os.path.join(d, f)
            try:
                parse_check(p)
            except LexError:
                logger.exception('Lexer failure: {0}'.format(os.path.basename(p)))

    logger.info("***** finished *****")


if __name__ == '__main__':
    #debug_lexer()
    #debug_parser()
    test()

