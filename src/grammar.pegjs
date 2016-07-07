/**
 * sqlite-parser grammar
 */

/* Start Grammar */
start
  = o semi_optional s:( stmt_list )? semi_optional
  {
    return util.extend({}, s);
  }

stmt_list
  = f:( stmt ) o b:( stmt_list_tail )*
  {
    return {
      'statement': util.listify(f, b)
    };
  }

semi_optional
  = ( sym_semi )*

semi_required
  = ( sym_semi )+

/**
 * @note
 *  You need semicolon between multiple statements, otherwise can omit last
 *  semicolon in a group of statements.
 */
stmt_list_tail
  = semi_required s:( stmt ) o
  { return s; }

/**
 * Expression definition reworked without left recursion for pegjs
 * {@link https://www.sqlite.org/lang_expr.html}
 */
expression "Expression"
  = t:( expression_concat / expression_types ) o
  { return t; }

expression_types
  = expression_wrapped / expression_unary / expression_node / expression_value

expression_concat "Logical Expression Group"
  = l:( expression_types ) o o:( binary_loop_concat ) o r:( expression )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': util.key(o),
      'left': l,
      'right': r
    };
  }

expression_wrapped "Wrapped Expression"
  = sym_popen n:( expression ) o sym_pclose
  { return n; }

expression_value
  = expression_cast
  / expression_exists
  / expression_case
  / expression_raise
  / bind_parameter
  / function_call
  / literal_value
  / id_column

expression_unary "Unary Expression"
  = o:( operator_unary ) e:( expression_types )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'operation',
      'expression': e,
      'operator': util.key(o)
    };
  }

expression_cast "CAST Expression"
  = s:( CAST ) o sym_popen e:( expression ) o a:( type_alias ) o sym_pclose
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': util.key(s),
      'expression': e,
      'as': a
    };
  }

type_alias "Type Alias"
  = AS o d:( type_definition )
  { return d; }

expression_exists "EXISTS Expression"
  = n:( expression_exists_ne ) o e:( select_wrapped )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'exists',
      'expression': e,
      'operator': util.key(n)
    };
  }

expression_exists_ne "EXISTS Keyword"
  = n:( expression_is_not )? x:( EXISTS ) o
  { return util.compose([n, x]); }

expression_case "CASE Expression"
  = t:( CASE ) o e:( expression )? o w:( expression_case_when )+ o
    s:( expression_case_else )? o END o
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': util.key(t),
      'expression': e,
      'condition': util.listify(w, s)
    };
  }

expression_case_when "WHEN Clause"
  = s:( WHEN ) o w:( expression ) o THEN o t:( expression ) o
  {
    return {
      'type': 'condition',
      'format': util.key(s),
      'when': w,
      'then': t
    };
  }

expression_case_else "ELSE Clause"
  = s:( ELSE ) o e:( expression ) o
  {
    return {
      'type': 'condition',
      'format': util.key(s),
      'else': e
    };
  }

expression_raise "RAISE Expression"
  = s:( RAISE ) o sym_popen o a:( expression_raise_args ) o sym_pclose
  {
    return util.extend({
      'type': 'expression',
      'format': 'unary',
      'variant': util.key(s),
      'expression': a
    }, a);
  }

expression_raise_args "RAISE Expression Arguments"
  = a:( raise_args_ignore / raise_args_message )
  {
    return util.extend({
      'type': 'error'
    }, a);
  }

raise_args_ignore "IGNORE Keyword"
  = f:( IGNORE )
  {
    return {
      'action': util.key(f)
    };
  }

raise_args_message
  = f:( ROLLBACK / ABORT / FAIL ) o sym_comma o m:( error_message )
  {
    return {
      'action': util.key(f),
      'message': m
    };
  }

/* Expression Nodes */
expression_node
  = expression_collate
  / expression_compare
  / expression_null
  / expression_between
  / expression_in
  / stmt_select
  / operation_binary

/** @note Removed expression on left-hand-side to remove recursion */
expression_collate "COLLATE Expression"
  = v:( expression_value ) o s:( COLLATE ) o c:( id_collation )
  {
    return util.extend(v, {
      'collate': c
    });
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_compare "Comparison Expression"
  = v:( expression_value ) o n:( expression_is_not )?
    m:( LIKE / GLOB / REGEXP / MATCH / CONTAINS ) o e:( expression ) o
    x:( expression_escape )?
  {
    return util.extend({
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': util.keyify([n, m]),
      'left': v,
      'right': e
    }, x);
  }

expression_escape "ESCAPE Expression"
  = s:( ESCAPE ) o e:( expression )
  {
    return {
      'escape': e
    };
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_null "NULL Expression"
  = v:( expression_value ) o n:( expression_null_nodes )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'operation',
      'expression': v,
      'operation': n
    };
  }

expression_null_nodes "NULL Keyword"
  = i:( "IS"i / expression_is_not_join ) n:( NULL ) o
  { return util.keyify([i, n]); }

expression_isnt "IS Keyword"
  = i:( IS ) o n:( expression_is_not )?
  { return util.keyify([i, n]); }

expression_is_not
  = n:( NOT ) o
  { return util.textNode(n); }

expression_is_not_join
  = t:( "NOT"i ) o
  { return util.key(t); }

/** @note Removed expression on left-hand-side to remove recursion */
expression_between "BETWEEN Expression"
  = v:( expression_value ) o n:( expression_is_not )? b:( BETWEEN ) o e1:( expression_types ) o s:( AND ) o e2:( expression_types )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': util.keyify([n, b]),
      'left': v,
      'right': {
        'type': 'expression',
        'format': 'binary',
        'variant': 'operation',
        'operation': util.key(s),
        'left': e1,
        'right': e2
      }
    };
  }


/** @note Removed expression on left-hand-side to remove recursion */
expression_in "IN Expression"
  = v:( expression_value ) o n:( expression_is_not )? i:( IN ) o e:( expression_in_target )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': util.keyify([n, i]),
      'left': v,
      'right': e
    };
  }

expression_in_target
  = expression_list_or_select
  / id_table

expression_list_or_select
  = sym_popen e:( stmt_select / expression_list ) o sym_pclose
  { return e; }

/**
 * Type definitions
 */
 type_definition "Type Definition"
  = n:( datatype_types ) o a:( type_definition_args )?
  {
    return util.extend({
      'type': 'datatype',
      'variant': n[0],
      'affinity': n[1],
      'args': [] // datatype definition arguments
    }, a);
  }

type_definition_args "Type Definition Arguments"
  = sym_popen a1:( literal_number_signed ) o a2:( definition_args_loop )? sym_pclose
  {
    return {
      'args': util.listify(a1, a2)
    };
  }

definition_args_loop
  = sym_comma o n:( literal_number_signed ) o
  { return n; }

/**
 * Literal value definition
 * {@link https://www.sqlite.org/syntax/literal-value.html}
 */
literal_value
  = literal_number
  / literal_string
  / literal_blob
  / literal_null
  / literal_date

literal_null "Null Literal"
  = n:( NULL ) o
  {
    return {
      'type': 'literal',
      'variant': 'null',
      'value': util.key(n)
    };
  }

literal_date "Date Literal"
  = d:( CURRENT_DATE / CURRENT_TIMESTAMP / CURRENT_TIME ) o
  {
    return {
      'type': 'literal',
      'variant': 'date',
      'value': util.key(d)
    };
  }

/**
 * Notes:
 *    1) [ENFORCED] SQL uses single quotes for string literals.
 *    2) [NOT IMPLEMENTED] Value is an identier or a string literal based on context.
 * {@link https://www.sqlite.org/lang_keywords.html}
 */
literal_string "String Literal"
  = s:( literal_string_single )
  {
    return {
      'type': 'literal',
      'variant': 'string',
      'value': s
    };
  }

literal_string_single "Single-quoted String Literal"
  = sym_sglquote s:( literal_string_schar )* sym_sglquote
  {
    /**
      * @note Unescaped the pairs of literal single quotation marks
      * @note Not sure if the BLOB type should be un-escaped
      */
    return util.unescape(s, "'");
  }

literal_string_schar
  = "''"
  / [^\']

literal_blob "Blob Literal"
  = [x]i b:( literal_string_single )
  {
    return {
      'type': 'literal',
      'variant': 'blob',
      'value': b
    };
  }

number_sign "Number Sign"
  = s:( sym_plus / sym_minus )
  { return s; }

literal_number_signed
  = s:( number_sign )? n:( literal_number )
  {
    if (util.isOkay(s)) {
      n['value'] = util.textMerge(s, n['value']);
    }
    return n;
  }

literal_number
  = literal_number_decimal
  / literal_number_hex

literal_number_decimal
  = d:( number_decimal_node ) e:( number_decimal_exponent )?
  {
    return {
      'type': 'literal',
      'variant': 'decimal',
      'value': util.textMerge(d, e)
    };
  }

number_decimal_node "Decimal Literal"
  = number_decimal_full
  / number_decimal_fraction

number_decimal_full
  = f:( number_digit )+ b:( number_decimal_fraction )?
  { return util.textMerge(f, b); }

number_decimal_fraction
  = t:( sym_dot ) d:( number_digit )+
  { return util.textMerge(t, d); }

number_decimal_exponent "Decimal Literal Exponent"
  = e:( "E"i ) s:( [\+\-] )? d:( number_digit )+
  { return util.textMerge(e, s, d); }

literal_number_hex "Hexidecimal Literal"
  = f:( "0x"i ) b:( number_hex )*
  {
    return {
      'type': 'literal',
      'variant': 'hexidecimal',
      'value': util.textMerge(f, b)
    };
  }

number_hex
  = [0-9a-f]i

number_digit
  = [0-9]

/**
 * Bind Parameters have several syntax variations:
 * 1) "?" ( [0-9]+ )?
 * 2) [\$\@\:] name_char+
 * {@link https://www.sqlite.org/c3ref/bind_parameter_name.html}
 */
bind_parameter "Bind Parameter"
  = b:( bind_parameter_numbered / bind_parameter_named / bind_parameter_tcl )
  {
    return util.extend({
      'type': 'variable'
    }, b);
  }

/**
 * Bind parameters start at index 1 instead of 0.
 */
bind_parameter_numbered "Numbered Bind Parameter"
  = q:( sym_quest ) id:( [1-9] [0-9]* )? o
  {
    return {
      'format': 'numbered',
      'name': util.textMerge(q, id)
    };
  }

bind_parameter_named "Named Bind Parameter"
  = s:( [\:\@] ) name:( name_char )+ o
  {
    return {
      'format': 'named',
      'name': util.textMerge(s, name)
    };
  }

bind_parameter_tcl "TCL Bind Parameter"
  = d:( "$" ) name:( name_char / ":" )+ o s:( tcl_suffix )?
  {
    return util.extend({
      'format': 'tcl',
      'name': util.textMerge(d, name)
    }, s);
  }

tcl_suffix
  = sfx:( name_dblquoted ) o
  {
    return {
      'suffix': sfx
    };
  }

/** @note Removed expression on left-hand-side to remove recursion */
operation_binary "Binary Expression"
  = v:( expression_value ) o o:( operator_binary ) o e:( expression_types )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': util.key(o),
      'left': v,
      'right': e
    };
  }

binary_loop_concat
  = c:( AND / OR ) o
  { return util.key(c); }

expression_list "Expression List"
  = f:( expression ) o rest:( expression_list_rest )*
  {
    return util.listify(f, rest);
  }

expression_list_rest
  = sym_comma e:( expression ) o
  { return e; }

function_call "Function Call"
  = n:( name_unquoted ) o sym_popen a:( function_call_args )? o sym_pclose
  {
    return util.extend({
      'type': 'function',
      'name': n,
      'args': []
    }, a);
  }

function_call_args "Function Call Arguments"
  = ( s:( select_star ) ) {
    return {
      'args': [{
        'type': 'identifier',
        'variant': 'star',
        'name': s
      }]
    };
  }
  / ( d:( args_list_distinct )? e:( expression_list ) ) {
    return util.extend({
      'args': e
    }, d);
  }

args_list_distinct
  = s:( DISTINCT ) o
  {
    return {
      'filter': util.key(s)
    };
  }

error_message "Error Message"
  = m:( literal_string )
  { return m; }

stmt "Statement"
  = m:( stmt_modifier )? s:( stmt_nodes ) o
  {
    return util.extend(s, m);
  }

stmt_modifier "QUERY PLAN"
  = e:( EXPLAIN ) o q:( modifier_query )?
  {
    return {
      'explain': util.isOkay(e)
    };
  }

modifier_query "QUERY PLAN Keyword"
  = q:( QUERY ) o p:( PLAN ) o
  { return util.compose([q, p]); }

stmt_nodes
  = stmt_crud
  / stmt_create
  / stmt_drop
  / stmt_transaction
  / stmt_alter
  / stmt_rollback
  / stmt_savepoint
  / stmt_release
  / stmt_sqlite

/**
 * @note
 *  Transaction statement rules do not follow the transaction nesting rules
 *  for the BEGIN, COMMIT, and ROLLBACK statements.
 *  {@link https://www.sqlite.org/lang_savepoint.html}
 */
stmt_transaction "Transaction"
  = b:( stmt_begin ) s:( stmt_list )? e:( stmt_commit )
  {
    return util.extend({
      'type': 'statement',
      'variant': 'transaction'
    }, b, s);
  }

stmt_commit "END Transaction Statement"
  = s:( COMMIT / END ) o t:( commit_transaction )?
  {
    return util.keyify([s, t]);
  }

stmt_begin "BEGIN Transaction Statement"
  = s:( BEGIN ) o m:( stmt_begin_modifier )? t:( commit_transaction )?
  {
    return util.extend({}, m);
  }

commit_transaction
  = t:( TRANSACTION ) o
  { return t; }

stmt_begin_modifier
  = m:( DEFERRED / IMMEDIATE / EXCLUSIVE ) o
  {
    return {
      'defer': util.key(m)
    };
  }

stmt_rollback "ROLLBACK Statement"
  = s:( ROLLBACK ) o ( commit_transaction )? n:( rollback_savepoint )?
  {
    return {
      'type': 'statement',
      'variant': util.key(s),
      'to': n
    };
  }

rollback_savepoint "TO Clause"
  = TO o ( savepoint_alt )? n:( id_savepoint ) o
  { return n; }

savepoint_alt
  = s:( SAVEPOINT ) o
  { return util.key(s); }

stmt_savepoint "SAVEPOINT Statement"
  = s:( savepoint_alt ) n:( id_savepoint ) o
  {
    return {
      'type': 'statement',
      'variant': s,
      'target': n
    };
  }

stmt_release "RELEASE Statement"
  = s:( RELEASE ) o a:( savepoint_alt )? n:( id_savepoint ) o
  {
    return {
      'type': 'statement',
      'variant': util.key(s),
      'target': n
    };
  }

stmt_alter "ALTER TABLE Statement"
  = s:( alter_start ) n:( id_table ) o e:( alter_action ) o
  {
    return {
      'type': 'statement',
      'variant': util.key(s)
    };
  }

alter_start "ALTER TABLE Keyword"
  = a:( ALTER ) o t:( TABLE ) o
  { return util.compose([a, t]); }

alter_action
  = alter_action_rename
  / alter_action_add

alter_action_rename "RENAME TO Keyword"
  = s:( RENAME ) o TO o n:( id_table )
  {
    return {
      'action': util.key(s),
      'name': n
    };
  }

alter_action_add "ADD COLUMN Keyword"
  = s:( ADD ) o ( action_add_modifier )? d:( source_def_column )
  {
    return {
      'action': util.key(s),
      'definition': d
    };
  }

action_add_modifier
  = s:( COLUMN ) o
  { return util.key(s); }

stmt_crud
  = w:( stmt_core_with ) s:( stmt_crud_types )
  { return util.extend(s, w); }

stmt_core_with "WITH Clause"
  = w:( clause_with )? o
  {
    return w;
  }

clause_with
  = s:( WITH ) o v:( clause_with_recursive )? t:( clause_with_tables )
  {
    var recursive = {
      'variant': util.isOkay(v) ? 'recursive' : 'common'
    };
    if (util.isArrayOkay(t)) {
      // Add 'recursive' property into each table expression
      t = t.map(function (elem) {
        return util.extend(elem, recursive);
      });
    }
    return {
      'with': t
    };
  }

clause_with_recursive
  = s:( RECURSIVE ) o
  { return util.key(s); }

clause_with_tables
  = f:( expression_cte ) o r:( clause_with_loop )*
  { return util.listify(f, r); }

clause_with_loop
  = sym_comma e:( expression_cte ) o
  { return e; }

expression_cte "Common Table Expression"
  = t:( id_cte ) s:( select_alias )
  {
    return util.extend({
      'type': 'expression',
      'format': 'table',
      'variant': 'common',
      'target': t
    }, s);
  }

select_alias
  = AS o s:( select_wrapped )
  {
    return {
      'expression': s
    };
  }

select_wrapped
  = sym_popen s:( stmt_select ) o sym_pclose
  { return s; }

/**
 * @note Uncommon or SQLite-specific statement types
 */
stmt_sqlite
  = stmt_detach
  / stmt_vacuum
  / stmt_analyze
  / stmt_reindex
  / stmt_pragma

stmt_detach "DETACH Statement"
  = d:( DETACH ) o b:( DATABASE o )? n:( id_database ) o
  {
    return {
      'type': 'statement',
      'variant': util.key(d),
      'target': n
    };
  }

stmt_vacuum "VACUUM Statement"
  = v:( VACUUM ) o
  {
    return {
      'type': 'statement',
      'variant': 'vacuum'
    };
  }

/**
 * @note
 *  The argument from this statement cannot be categorized as a
 *  table or index based on context, so only the name is included.
 */
stmt_analyze "ANALYZE Statement"
  = s:( ANALYZE ) o a:( analyze_arg )?
  {
    return util.extend({
      'type': 'statement',
      'variant': util.key(s)
    }, a);
  }

analyze_arg
  = n:( id_table / id_index / id_database ) o
  {
    return {
      'target': n['name']
    };
  }

/**
 * @note
 *  The argument from this statement cannot be categorized as a
 *  table or index based on context, so only the name is included.
 */
stmt_reindex "REINDEX Statement"
  = s:( REINDEX ) o a:( reindex_arg )? o
  {
    return util.extend({
      'type': 'statement',
      'variant': util.key(s)
    }, a);
  }

reindex_arg
  = a:( id_table / id_index / id_collation ) o
  {
    return {
      'target': a['name']
    };
  }

stmt_pragma "PRAGMA Statement"
  = s:( PRAGMA ) o n:( id_pragma ) o v:( pragma_expression )?
  {
    return {
      'type': 'statement',
      'variant': util.key(s),
      'target': n,
      'args': (util.isOkay(v) ? util.makeArray(v) : [])
    };
  }

pragma_expression
  = ( sym_equal v:( pragma_value ) o ) { return v; }
  / ( sym_popen v:( pragma_value ) o sym_pclose ) { return v; }

pragma_value
  = pragma_value_bool
  / pragma_value_literal
  / pragma_value_name

pragma_value_literal
  = v:( literal_number_signed / literal_string )
  { return v; }

/**
 * @note
 *  This method allows all possible values EXCEPT an unquoted 'no',
 *  because that is a reserved word.
 * @note
 *  There is no such thing as a boolean literal in SQLite
 *  {@link http://www.sqlite.org/datatype3.html}. However, the
 *  documentation for PRAGMA mentions the ability to use
 *  literal boolean values in this one specific instance.
 *  See: {@link https://www.sqlite.org/pragma.html}
 */
pragma_value_bool
  = v:( name ) & { return /^(yes|no|false|true|0|1)$/i.test(v) }
  {
    return {
      'type': 'literal',
      'variant': 'boolean',
      'normalized': (/^(yes|true|1)$/i.test(v) ? '1' : '0'),
      'value': v
    };
  }

pragma_value_name
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'name',
      'name': n
    };
  }

stmt_crud_types
  = stmt_select
  / stmt_insert
  / stmt_update
  / stmt_delete

/** {@link https://www.sqlite.org/lang_select.html} */
stmt_select "SELECT Statement"
  = s:( select_loop ) o o:( stmt_core_order )? o l:( stmt_core_limit )?
  {
    return util.extend(s, o, l);
  }

stmt_core_order "ORDER BY Clause"
  = ORDER o BY o d:( stmt_core_order_list )
  {
    return {
      'order': d['result']
    };
  }

stmt_core_limit "LIMIT Clause"
  = s:( LIMIT ) o e:( expression ) o d:( stmt_core_limit_offset )?
  {
    return {
      'limit': util.extend({
        'type': 'expression',
        'variant': 'limit',
        'start': e
      }, d)
    };
  }

stmt_core_limit_offset "OFFSET Clause"
  = o:( limit_offset_variant ) e:( expression )
  {
    return {
      'offset': e
    };
  }

limit_offset_variant
  = limit_offset_variant_name
  / sym_comma

limit_offset_variant_name
  = s:( OFFSET ) o
  { return util.key(s); }

select_loop
  = s:( select_parts ) o u:( select_loop_union )*
  {
    if (util.isArrayOkay(u)) {
      return {
        'type': 'statement',
        'variant': 'compound',
        'statement': s,
        'compound': u
      };
    } else {
      return s;
    }
  }

select_loop_union "Union Operation"
  = c:( operator_compound ) o s:( select_parts ) o
  {
    return {
      'type': 'compound',
      'variant': c,
      'statement': s
    };
  }

select_parts
  = select_parts_core
  / select_parts_values

select_parts_core
  = s:( select_core_select ) f:( select_core_from )? w:( stmt_core_where )?
    g:( select_core_group )?
  {
    return util.extend({
      'type': 'statement',
      'variant': 'select',
    }, s, f, w, g);
  }

select_core_select "SELECT Results Clause"
  = SELECT o d:( select_modifier )? o t:( select_target )
  {
    return util.extend({
      'result': t
    }, d);
  }

select_modifier "SELECT Results Modifier"
  = select_modifier_distinct
  / select_modifier_all

select_modifier_distinct
  = s:( DISTINCT ) o
  {
    return {
      'distinct': true
    };
  }

select_modifier_all
  = s:( ALL ) o
  {
    return {};
  }

select_target
  = f:( select_node ) o r:( select_target_loop )*
  { return util.listify(f, r); }

select_target_loop
  = sym_comma n:( select_node ) o
  { return n; }

select_core_from "FROM Clause"
  = s:( FROM ) o s:( select_source ) o
  {
    return {
      'from': s
    };
  }

stmt_core_where "WHERE Clause"
  = s:( WHERE ) o e:( expression ) o
  {
    return {
      'where': util.makeArray(e)
    };
  }

select_core_group "GROUP BY Clause"
  = s:( GROUP ) o BY o e:( expression_list ) o h:( select_core_having )?
  {
    return util.extend({
      'group': util.makeArray(e)
    }, h);
  }

select_core_having "HAVING Clause"
  = s:( HAVING ) o e:( expression ) o
  {
    return {
      'having': e
    };
  }

select_node
  = select_node_star
  / select_node_aliased

select_node_star
  = q:( select_node_star_qualified )? s:( select_star )
  {
    return {
      'type': 'identifier',
      'variant': 'star',
      'name': util.textMerge(q, s)
    };
  }

select_node_star_qualified
  = n:( name ) s:( sym_dot )
  { return util.textMerge(n, s); }

select_node_aliased
  = e:( expression ) o a:( alias )?
  {
    return util.extend(e, a);
  }

select_source
  = select_join_loop
  / select_source_loop

select_source_loop
  = f:( table_or_sub ) o t:( source_loop_tail )*
  { return util.listify(f, t); }

source_loop_tail
  = sym_comma t:( table_or_sub ) o
  { return t; }

table_or_sub
  = table_or_sub_sub
  / table_qualified
  / table_or_sub_select

table_qualified "Qualified Table"
  = d:( table_qualified_id ) o i:( table_or_sub_index_node )?
  {
    return util.extend(d, i);
  }

table_qualified_id "Qualified Table Identifier"
  = n:( id_table ) o a:( alias )?
  {
    return util.extend(n, a);
  }


table_or_sub_index_node "Qualfied Table Index"
  = index_node_indexed
  / index_node_none

index_node_indexed
  = s:( INDEXED ) o BY o n:( name ) o
  {
    return {
      'index': n
    };
  }

index_node_none
  = n:( expression_is_not ) i:( INDEXED ) o
  {
    // TODO: Not sure what should happen here
    return {
      'index': util.keyify([n, i])
    };
  }

table_or_sub_sub "SELECT Source"
  = sym_popen l:( select_source ) o sym_pclose
  { return l; }

table_or_sub_select "Subquery"
  = s:( select_wrapped ) a:( alias )?
  {
    return util.extend(s, a);
  }

alias "Alias"
  = a:( AS ( !name_char o ) )? n:( name ) o
  {
    return {
      'alias': n
    };
  }

select_join_loop
  = t:( table_or_sub ) o j:( select_join_clause )+
  {
    return {
      'type': 'map',
      'variant': 'join',
      'source': t,
      'map': j
    };
  }

select_join_clause "JOIN Operation"
  = o:( join_operator ) o n:( table_or_sub ) o c:( join_condition )?
  {
    return {
      'type': 'join',
      'variant': util.key(o),
      'source': n,
      'constraint': c
    };
  }

join_operator "JOIN Operator"
  = n:( join_operator_natural )? o t:( join_operator_types )? j:( JOIN )
  { return util.compose([n, t, j]); }

join_operator_natural
  = n:( NATURAL ) o
  { return util.textNode(n); }

join_operator_types
  = operator_types_hand
  / operator_types_misc

/**
 * @note FULL (OUTER)? JOIN included from PostgreSQL although it is not a
 *  join operarator allowed in SQLite.
 *  See: {@link https://www.sqlite.org/syntax/join-operator.html}
 */
operator_types_hand
  = t:( LEFT / RIGHT / FULL ) o o:( types_hand_outer )?
  { return util.compose([t, o]); }

types_hand_outer
  = t:( OUTER ) o
  { return util.textNode(t); }

operator_types_misc
  = t:( INNER / CROSS ) o
  { return util.textNode(t); }

join_condition "JOIN Constraint"
  = c:( join_condition_on / join_condition_using )
  {
    return util.extend({
      'type': 'constraint',
      'variant': 'join'
    }, c);
  }

join_condition_on "Join ON Clause"
  = s:( ON ) o e:( expression )
  {
    return {
      'format': util.key(s),
      'on': e
    };
  }

join_condition_using "Join USING Clause"
  = s:( USING ) o e:( loop_columns )
  {
    return {
      'format': util.key(s),
      'using': e
    };
  }


select_parts_values "VALUES Clause"
  = s:( VALUES ) o l:( insert_values_list )
  {
    return util.extend({
      'type': 'statement',
      'variant': 'select'
    }, l);
  }

stmt_core_order_list
  = f:( stmt_core_order_list_item ) o b:( stmt_core_order_list_loop )*
  {
    return {
      'result': util.listify(f, b)
    };
  }

stmt_core_order_list_loop
  = sym_comma i:( stmt_core_order_list_item ) o
  { return i; }

stmt_core_order_list_item "Ordering Expression"
  = e:( expression ) o c:( column_collate )? o d:( primary_column_dir )?
  {
    return util.extend({
      'type': 'expression',
      'variant': 'order',
      'expression': e
    }, c, d);
  }

select_star "Star"
  = sym_star

stmt_fallback_types "Fallback Type"
  = k:( REPLACE / ROLLBACK / ABORT / FAIL / IGNORE )
  { return k; }

/** {@link https://www.sqlite.org/lang_insert.html} */
stmt_insert "INSERT Statement"
  = k:( insert_keyword ) o t:( insert_target )
  {
    return util.extend({
      'type': 'statement',
      'variant': 'insert'
    }, k, t);
  }

insert_keyword
  = insert_keyword_ins
  / insert_keyword_repl

insert_keyword_ins "INSERT Keyword"
  = a:( INSERT ) o m:( insert_keyword_mod )?
  {
    return util.extend({
      'action': util.key(a)
    }, m);
  }

insert_keyword_repl "REPLACE Keyword"
  = a:( REPLACE ) o
  {
    return {
      'action': util.key(a)
    };
  }

insert_keyword_mod "INSERT OR Modifier"
  = s:( OR ) o m:( stmt_fallback_types )
  {
    return {
      'or': util.key(m)
    };
  }

insert_target
  = i:( insert_into ) r:( insert_results )
  {
    return util.extend({
      'into': i
    }, r);
  }

insert_into "INTO Clause"
  = s:( insert_into_start ) t:( id_cte )
  {
    return t;
  }

insert_into_start "INTO Keyword"
  = s:( INTO ) o

insert_results "VALUES Clause"
  = r:( insert_value / insert_select / insert_default ) o
  {
    return {
      'result': r
    };
  }

loop_columns "Column List"
  = sym_popen f:( loop_name ) o b:( loop_column_tail )* sym_pclose
  {
    return {
      'columns': util.listify(f, b)
    };
  }

loop_column_tail
  = sym_comma c:( loop_name ) o
  { return c; }

loop_name "Column Name"
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'column',
      'name': n
    };
  }

insert_value "VALUES Clause"
  = s:( insert_value_start ) r:( insert_values_list )
  { return r; }

insert_value_start "VALUES Keyword"
  = s:( VALUES ) o
  { return util.key(s); }

insert_values_list
  = f:( insert_values ) o b:( insert_values_loop )*
  { return util.listify(f, b); }

insert_values_loop
  = sym_comma e:( insert_values ) o
  { return e; }

insert_values "Insert Values List"
  = sym_popen e:( expression_list ) o sym_pclose
  {
    return {
      'type': 'values',
      'variant': 'list',
      'values': e
    };
  }

insert_select "SELECT Results Clause"
  = stmt_select

insert_default "DEFAULT VALUES Clause"
  = d:( DEFAULT ) o v:( VALUES )
  {
    return {
      'type': 'values',
      'variant': 'default'
      // TODO: Not sure what should go here
      // , 'values': null
    };
  }

operator_compound "Compound Operator"
  = s:( compound_union / INTERSECT / EXCEPT )
  { return util.key(s); }

compound_union "UNION Operator"
  = s:( UNION ) o a:( compound_union_all )?
  { return util.compose([s, a]); }

compound_union_all
  = a:( ALL ) o
  { return a; }

/**
 * @note Includes limited update syntax {@link https://www.sqlite.org/syntax/update-stmt-limited.html}
 */
stmt_update "UPDATE Statement"
  = s:( update_start ) f:( update_fallback )?
    t:( table_qualified ) o u:( update_set ) w:( stmt_core_where )?
    o:( stmt_core_order )? o l:( stmt_core_limit )?
  {
    return util.extend({
      'type': 'statement',
      'variant': s,
      'into': t
    }, f, u, w, o, l);
  }

update_start "UPDATE Keyword"
  = s:( UPDATE ) o
  { return util.key(s); }

update_fallback "UPDATE OR Modifier"
  = OR o t:( stmt_fallback_types ) o
  {
    return {
      'or': util.key(t)
    };
  }

update_set "SET Clause"
  = SET o c:( update_columns ) o
  {
    return {
      'set': c
    };
  }

update_columns
  = f:( update_column ) b:( update_columns_tail )*
  { return util.listify(f, b); }

update_columns_tail
  = o sym_comma c:( update_column )
  { return c; }

update_column "Column Assignment"
  = f:( id_column ) o sym_equal e:( expression_types ) o
  {
    return {
      'type': 'assignment',
      'target': f,
      'value': e
    };
  }

/**
 * @note Includes limited update syntax {@link https://www.sqlite.org/syntax/delete-stmt-limited.html}
 */


stmt_delete "DELETE Statement"
  = s:( delete_start ) t:( table_qualified ) o w:( stmt_core_where )?
    o:( stmt_core_order )? l:( stmt_core_limit )?
  {
    return util.extend({
      'type': 'statement',
      'variant': s,
      'from': t
    }, w, o, l);
  }

delete_start "DELETE Keyword"
  = s:( DELETE ) o FROM o
  { return util.key(s); }

/**
 * @note
 *  The "only" rules were created to help the tracer to not traverse
 *  the wrong path.
 */
stmt_create "CREATE Statement"
  = create_table_only
  / create_index_only
  / create_trigger_only
  / create_view_only
  / create_virtual_only

create_start
  = s:( CREATE ) o
  { return util.key(s); }

create_table_only
  = !( create_start ( INDEX / TRIGGER / VIEW / VIRTUAL ) ) c:( create_table )
  { return c; }

create_index_only
  = !( create_start ( TABLE / TRIGGER / VIEW / VIRTUAL ) ) c:( create_index )
  { return c; }

create_trigger_only
  = !( create_start ( TABLE / INDEX / VIEW / VIRTUAL ) ) c:( create_trigger )
  { return c; }

create_view_only
  = !( create_start ( TABLE / INDEX / TRIGGER / VIRTUAL ) ) c:( create_view )
  { return c; }

create_virtual_only
  = !( create_start ( TABLE / INDEX / TRIGGER / VIEW ) ) c:( create_virtual )
  { return c; }

create_table "CREATE TABLE Statement"
  = s:( create_table_start ) ne:( create_core_ine )? id:( id_table ) o
    r:( create_table_source )
  {
    return util.extend({
      'type': 'statement',
      'name': id
    }, s, r, ne);
  }

create_table_start
  = s:( create_start ) tmp:( create_core_tmp )? t:( TABLE ) o
  {
    return util.extend({
      'variant': s,
      'format': util.key(t)
    }, tmp);
  }

create_core_tmp
  = t:( TEMPORARY / TEMP ) o
  {
    return {
      'temporary': util.isOkay(t)
    };
  }

create_core_ine "IF NOT EXISTS Modifier"
  = i:( IF ) o n:( expression_is_not ) e:( EXISTS ) o
  {
    return {
      'condition': util.makeArray({
        'type': 'condition',
        'condition': util.keyify([i, n, e])
      })
    };
  }

create_table_source
  = table_source_def
  / table_source_select

table_source_def "Table Definition"
  = sym_popen s:( source_def_loop ) t:( source_tbl_loop )* sym_pclose r:( source_def_rowid )?
  {
    return util.extend({
      'definition': util.listify(s, t)
    }, r);
  }

source_def_rowid
  = r:( WITHOUT ) o w:( ROWID ) o
  {
    return {
      'optimization': [{
        'type': 'optimization',
        'value': util.keyify([r, w])
      }]
    };
  }

source_def_loop
  = f:( source_def_column ) o b:( source_def_tail )*
  { return util.listify(f, b); }

source_def_tail
  = sym_comma t:( source_def_column ) o
  { return t; }

source_tbl_loop
  = sym_comma f:( table_constraint )
  { return f; }

/** {@link https://www.sqlite.org/syntaxdiagrams.html#column-def} */
source_def_column "Column Definition"
  = n:( name ) ( !( name_char ) o ) t:( column_type )? o c:( column_constraints )?
  {
    return util.extend({
      'type': 'definition',
      'variant': 'column',
      'name': n,
      'definition': (util.isOkay(c) ? c : []),
    }, t);
  }

column_type "Column Datatype"
  = t:( type_definition )
  {
    return {
      'datatype': t
    };
  }

column_constraints
  = f:( column_constraint ) b:( column_constraint_tail )* o
  { return util.listify(f, b); }

column_constraint_tail
  = o c:( column_constraint )
  { return c; }

/** {@link https://www.sqlite.org/syntax/column-constraint.html} */
column_constraint "Column Constraint"
  = n:( column_constraint_name )? c:( column_constraint_types )
  {
    return util.extend(c, n);
  }

column_constraint_name "Column Constraint Name"
  = CONSTRAINT o n:( name ) o
  {
    return {
      'name': n
    };
  }

column_constraint_types
  = column_constraint_primary
  / column_constraint_null
  / column_constraint_check
  / column_constraint_default
  / column_constraint_collate
  / column_constraint_foreign

column_constraint_foreign "FOREIGN KEY Column Constraint"
  = f:( foreign_clause )
  {
    return util.extend({
      'variant': 'foreign key'
    }, f);
  }

column_constraint_primary "PRIMARY KEY Column Constraint"
  = p:( col_primary_start ) d:( primary_column_dir )? c:( primary_conflict )?
    a:( col_primary_auto )?
  {
    return util.extend(p, c, d, a);
  }

col_primary_start "PRIMARY KEY Keyword"
  = s:( PRIMARY ) o k:( KEY ) o
  {
    return {
      'type': 'constraint',
      'variant': util.keyify([s, k])
    };
  }

col_primary_auto "AUTOINCREMENT Keyword"
  = a:( AUTOINCREMENT ) o
  {
    return {
      'autoIncrement': true
    };
  }

column_constraint_null
  = s:( constraint_null_types ) c:( primary_conflict )? o
  {
    return util.extend({
      'type': 'constraint',
      'variant': s
    }, c);
  }

constraint_null_types "UNIQUE Column Constraint"
  = t:( constraint_null_value / UNIQUE )
  { return util.key(t); }

constraint_null_value "NULL Column Constraint"
  = n:( expression_is_not )? l:( NULL )
  { return util.compose([n, l]); }

column_constraint_check "CHECK Column Constraint"
  = constraint_check

column_constraint_default "DEFAULT Column Constraint"
  = s:( DEFAULT ) o v:( expression_wrapped / literal_number_signed / literal_value )
  {
    return {
      'type': 'constraint',
      'variant': util.key(s),
      'value': v
    };
  }

column_constraint_collate "COLLATE Column Constraint"
  = c:( column_collate )
  {
    return {
      'type': 'constraint',
      'variant': 'collate',
      'collate': c
    };
  }

/** {@link https://www.sqlite.org/syntax/table-constraint.html} */
table_constraint "Table Constraint"
  = n:( table_constraint_name )? o c:( table_constraint_types ) o
  {
    return util.extend({
      'type': 'definition',
      'variant': 'constraint'
    }, c, n);
  }

table_constraint_name "Table Constraint Name"
  = CONSTRAINT o n:( name )
  {
    return {
      'name': n
    };
  }

table_constraint_types
  = table_constraint_foreign
  / table_constraint_primary
  / table_constraint_check

table_constraint_check "CHECK Table Constraint"
  = c:( constraint_check )
  {
    return {
      'definition': util.makeArray(c)
    };
  }

table_constraint_primary "PRIMARY KEY Table Constraint"
  = k:( primary_start ) o c:( primary_columns ) t:( primary_conflict )?
  {
    return {
      'definition': util.makeArray(util.extend(k, t)),
      'columns': c
    };
  }

primary_start
  = s:( primary_start_normal / primary_start_unique ) o
  {
    return {
      'type': 'constraint',
      'variant': util.key(s)
    };
  }

primary_start_normal "PRIMARY KEY Keyword"
  = p:( PRIMARY ) o k:( KEY )
  { return util.compose([p, k]); }

primary_start_unique "UNIQUE Keyword"
  = u:( UNIQUE )
  { return util.textNode(u); }

primary_columns "PRIMARY KEY Columns"
  = sym_popen f:( primary_column ) o b:( primary_column_tail )* sym_pclose
  { return util.listify(f, b); }

primary_column "Indexed Column"
  = e:( name ) o c:( column_collate )? d:( primary_column_dir )?
  {
    return util.extend({
      'type': 'identifier',
      'variant': 'column',
      'format': 'indexed',
      'name': e
    }, c, d);
  }

column_collate "Column Collation"
  = COLLATE o n:( id_collation ) o
  {
    return {
      'collate': n
    };
  }

primary_column_dir "Column Direction"
  = t:( ASC / DESC ) o
  {
    return {
      'direction': util.key(t),
    };
  }

primary_column_tail
  = sym_comma c:( primary_column ) o
  { return c; }

primary_conflict
  = s:( primary_conflict_start ) o t:( stmt_fallback_types ) o
  {
    return {
      'conflict': util.key(t)
    };
  }

primary_conflict_start "ON CONFLICT Keyword"
  = o:( ON ) o c:( CONFLICT )
  { return util.keyify([o, c]); }

constraint_check
  = k:( CHECK ) o c:( expression_wrapped )
  {
    return {
      'type': 'constraint',
      'variant': util.key(k),
      'expression': c
    };
  }

table_constraint_foreign "FOREIGN KEY Table Constraint"
  = k:( foreign_start ) l:( loop_columns ) c:( foreign_clause ) o
  {
    return util.extend({
      'definition': util.makeArray(util.extend(k, c))
    }, l);
  }

foreign_start "FOREIGN KEY Keyword"
  = f:( FOREIGN ) o k:( KEY ) o
  {
    return {
      'type': 'constraint',
      'variant': util.keyify([f, k])
    };
  }

/** {@link https://www.sqlite.org/syntax/foreign-key-clause.html} */
foreign_clause
  = r:( foreign_references ) a:( foreign_actions )? d:( foreign_deferrable )?
  {
    return util.extend({
      'type': 'constraint',
      'action': a,
      'defer': d
    }, r);
  }

foreign_references "REFERENCES Clause"
  = s:( REFERENCES ) o t:( id_cte )
  {
    return {
      'references': t
    };
  }



foreign_actions
  = f:( foreign_action ) o b:( foreign_actions_tail )*
  { return util.collect([f, b], []); }

foreign_actions_tail
  = a:( foreign_action ) o
  { return a; }

foreign_action "FOREIGN KEY Action Clause"
  = foreign_action_on
  / foreign_action_match

foreign_action_on
  = m:( ON ) o a:( DELETE / UPDATE ) o n:( action_on_action )
  {
    return {
      'type': 'action',
      'variant': util.key(m),
      'action': util.key(n)
    };
  }

action_on_action "FOREIGN KEY Action"
  = on_action_set
  / on_action_cascade
  / on_action_none

on_action_set
  = s:( SET ) o v:( NULL / DEFAULT )
  { return util.compose([s, v]); }

on_action_cascade
  = c:( CASCADE / RESTRICT )
  { return util.textNode(c); }

on_action_none
  = n:( NO ) o a:( ACTION )
  { return util.compose([n, a]); }

/**
 * @note Not sure what kind of name this should be.
 */
foreign_action_match
  = m:( MATCH ) o n:( name )
  {
    return {
      'type': 'action',
      'variant': util.key(m),
      'action': n
    };
  }

foreign_deferrable "DEFERRABLE Clause"
  = n:( expression_is_not )? d:( DEFERRABLE ) o i:( deferrable_initially )?
  { return util.keyify([n, d, i]); }

deferrable_initially
  = i:( INITIALLY ) o d:( DEFERRED / IMMEDIATE ) o
  { return util.compose([i, d]); }

table_source_select
  = s:( create_as_select )
  {
    return {
      'definition': util.makeArray(s)
    };
  }

create_index "CREATE INDEX Statement"
  = s:( create_index_start ) ne:( create_core_ine )? n:( id_index ) o
    o:( index_on ) w:( stmt_core_where )?
  {
    return util.extend({
      'type': 'statement',
      'target': n,
      'on': o,
    }, s, ne, w);
  }

create_index_start
  = s:( create_start ) u:( index_unique )? i:( INDEX ) o
  {
    return util.extend({
      'variant': util.key(s),
      'format': util.key(i)
    }, u);
  }

index_unique
  = u:( UNIQUE ) o
  {
    return {
      'unique': true
    };
  }

index_on "ON Clause"
  = o:( ON ) o t:( name ) o c:( primary_columns )
  {
    return {
      'target': t,
      'columns': c
    };
  }

/**
 * @note
 *  This statement type has missing syntax restrictions that need to be
 *  enforced on UPDATE, DELETE, and INSERT statements in the trigger_action.
 *  See {@link https://www.sqlite.org/lang_createtrigger.html}.
 */
create_trigger "CREATE TRIGGER Statement"
  = s:( create_trigger_start ) ne:( create_core_ine )? n:( id_trigger ) o
    cd:( trigger_conditions ) ( ON ) o o:( name ) o
    me:( trigger_foreach )? wh:( trigger_when )? a:( trigger_action )
  {
    return util.extend({
      'type': 'statement',
      'target': n,
      'on': o,
      'event': cd,
      'by': (util.isOkay(me) ? me : 'row'),
      'action': util.makeArray(a)
    }, s, ne, wh);
  }

create_trigger_start
  = s:( create_start ) tmp:( create_core_tmp )? t:( TRIGGER ) o
  {
    return util.extend({
      'variant': util.key(s),
      'format': util.key(t)
    }, tmp);
  }

trigger_conditions "Conditional Clause"
  = m:( trigger_apply_mods )? d:( trigger_do )
  {
    return util.extend({
      'type': 'event'
    }, m, d);
  }

trigger_apply_mods
  = m:( BEFORE / AFTER / trigger_apply_instead ) o
  {
    return {
      'occurs': util.key(m)
    };
  }

trigger_apply_instead
  = i:( INSTEAD ) o o:( OF )
  { return util.compose([i, o]); }

trigger_do "Conditional Action"
  = trigger_do_on
  / trigger_do_update

trigger_do_on
  = o:( DELETE / INSERT ) o
  {
    return {
      'event': util.key(o)
    };
  }

trigger_do_update
  = s:( UPDATE ) o f:( do_update_of )?
  {
    return {
      'event': util.key(s),
      'of': f
    };
  }

do_update_of
  = s:( OF ) o c:( do_update_columns )
  { return c; }

do_update_columns
  = f:( loop_name ) o b:( loop_column_tail )*
  { return util.listify(f, b); }

/**
 *  @note
 *    FOR EACH STATEMENT is not supported by SQLite, but still included here.
 *    See {@link https://www.sqlite.org/lang_createtrigger.html}.
 */
trigger_foreach
  = f:( FOR ) o e:( EACH ) o r:( ROW / "STATEMENT"i ) o
  { return util.key(r); }

trigger_when "WHEN Clause"
  = w:( WHEN ) o e:( expression ) o
  { return e; }

trigger_action "Actions Clause"
  = s:( BEGIN ) o a:( action_loop ) o e:( END ) o
  { return a; }

action_loop
  = l:( action_loop_stmt )+
  { return l; }

action_loop_stmt
  = s:( stmt ) o semi_required
  { return s; }

create_view "CREATE VIEW Statement"
  = s:( create_view_start ) ne:( create_core_ine )? n:( id_view ) o
    r:( create_as_select )
  {
    return util.extend({
      'type': 'statement',
      'target': n,
      'result': r
    }, s, ne);
  }

create_view_start
  = s:( create_start ) tmp:( create_core_tmp )? v:( VIEW ) o
  {
    return util.extend({
      'variant': util.key(s),
      'format': util.key(v)
    }, tmp);
  }

create_as_select
  = s:( AS ) o r:( stmt_select ) o
  { return r; }

create_virtual "CREATE VIRTUAL TABLE Statement"
  = s:( create_virtual_start ) ne:( create_core_ine )? n:( id_table ) o
    ( USING ) o m:( virtual_module )
  {
    return util.extend({
      'type': 'statement',
      'target': n,
      'result': m
    }, s, ne);
  }

create_virtual_start
  = s:( create_start ) v:( VIRTUAL ) o t:( TABLE ) o
  {
    return {
      'variant': util.key(s),
      'format': util.key(v)
    };
  }

virtual_module
  = m:( name_unquoted ) o a:( virtual_args )?
  {
    return util.extend({
      'type': 'module',
      'name': m,
      'args': []
    }, a);
  }

virtual_args "Module Arguments"
  = sym_popen f:( virtual_arg_types ) o sym_pclose
  {
    return {
      'args': f
    };
  }

virtual_arg_types
  = virtual_arg_list
  / virtual_arg_def

virtual_arg_list
  = !( name o ( type_definition / column_constraint ) ) l:( expression_list )
  { return l; }

virtual_arg_def
  = l:( source_def_loop )
  { return l; }

stmt_drop "DROP Statement"
  = s:( drop_start ) q:( id_table ) o
  {
    /**
     * @note Manually copy in the correct variant for the target
     */
    return util.extend({
      'type': 'statement',
      'target': util.extend(q, {
                  'variant': s['format']
                })
    }, s);
  }

drop_start "DROP Keyword"
  = s:( DROP ) o t:( drop_types ) i:( drop_conditions )?
  {
     return util.extend({
       'variant': util.key(s),
       'format': t,
       'condition': []
     }, i);
  }

drop_types "DROP Type"
  = t:( TABLE / INDEX / TRIGGER / VIEW ) o
  { return util.key(t); }

drop_conditions
  = c:( drop_ie )
  {
    return {
      'condition': util.makeArray(c)
    };
  }

drop_ie "IF EXISTS Keyword"
  = i:( IF ) o e:( EXISTS ) o
  {
    return {
      'type': 'condition',
      'condition': util.keyify([i, e])
    };
  }

/* Unary and Binary Operators */

operator_unary "Unary Operator"
  = sym_tilde
  / sym_minus
  / sym_plus
  / expression_is_not

operator_binary "Binary Operator"
  = o:( binary_nodes )
  { return util.key(o); }

binary_nodes
  = binary_concat
  / expression_isnt
  / binary_multiply
  / binary_divide
  / binary_mod
  / binary_plus
  / binary_minus
  / binary_left
  / binary_right
  / binary_and
  / binary_or
  / binary_lte
  / binary_lt
  / binary_gte
  / binary_gt
  / binary_lang
  / binary_notequal
  / binary_equal

binary_concat "Or"
  = sym_pipe sym_pipe

binary_plus "Add"
  = sym_plus

binary_minus "Subtract"
  = sym_minus

binary_multiply "Multiply"
  = sym_star

binary_divide "Divide"
  = sym_fslash

binary_mod "Modulo"
  = sym_mod

binary_left "Shift Left"
  = sym_lt sym_lt

binary_right "Shift Right"
  = sym_gt sym_gt

binary_and "Logical AND"
  = sym_amp

binary_or "Logical OR"
  = sym_pipe

binary_lt "Less Than"
  = sym_lt

binary_gt "Greater Than"
  = sym_gt

binary_lte "Less Than Or Equal"
  = sym_lt sym_equal

binary_gte "Greater Than Or Equal"
  = sym_gt sym_equal

binary_equal "Equal"
  = sym_equal ( sym_equal )?

binary_notequal "Not Equal"
  = ( sym_excl sym_equal )
  / ( sym_lt sym_gt )

binary_lang
  = binary_lang_isnt
  / binary_lang_misc

binary_lang_isnt "IS"
  = i:( IS ) o n:( expression_is_not )?
  { return util.keyify([i, n]); }

binary_lang_misc
  = m:( IN / LIKE / GLOB / MATCH / REGEXP / CONTAINS )
  { return util.key(m); }

/* Database, Table and Column IDs */

id_database "Database Identifier"
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'database',
      'name': n
    };
  }

id_table "Table Identifier"
  = d:( id_table_qualified )? n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'table',
      'name': util.textMerge(d, n)
    };
  }

id_table_qualified
  = n:( name ) d:( sym_dot )
  { return util.textMerge(n, d); }

id_column "Column Identifier"
  = q:( column_qualifiers / id_column_qualified / column_unqualified ) n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'column',
      'name': util.textMerge(q, n)
    };
  }

column_unqualified
  = o
  { return ''; }

column_qualifiers
  = d:( id_table_qualified ) t:( id_column_qualified )
  { return util.textMerge(d, t); }

id_column_qualified
  = t:( name ) d:( sym_dot )
  { return util.textMerge(t, d); }

id_collation "Collation Identifier"
  = n:( name_unquoted )
  {
    return {
      'type': 'identifier',
      'variant': 'collation',
      'name': n
    };
  }

id_savepoint "Savepoint Indentifier"
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'savepoint',
      'name': n
    };
  }

id_index "Index Identifier"
  = d:( id_table_qualified )? n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'index',
      'name': util.textMerge(d, n)
    };
  }

id_trigger "Trigger Identifier"
  = d:( id_table_qualified )? n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'trigger',
      'name': util.textMerge(d, n)
    };
  }

id_view "View Identifier"
  = d:( id_table_qualified )? n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'view',
      'name': util.textMerge(d, n)
    };
  }

id_pragma "Pragma Identifier"
  = d:( id_table_qualified )? n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'pragma',
      'name': util.textMerge(d, n)
    };
  }

id_cte "CTE Identifier"
  = d:( id_table_expression / id_table ) o
  { return d; }

id_table_expression
  = n:( name ) o a:( loop_columns )
  {
    return util.extend({
      'type': 'identifier',
      'variant': 'expression',
      'format': 'table',
      'name': n,
      'columns': []
    }, a);
  }

id_constraint_table "Table Constraint Identifier"
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'constraint',
      'format': 'table',
      'name': n
    };
  }

id_constraint_column "Column Constraint Identifier"
  = n:( name )
  {
    return {
      'type': 'identifier',
      'variant': 'constraint',
      'format': 'column',
      'name': n
    };
  }

/* Column datatypes */

datatype_types "Datatype Name"
  = t:( datatype_text ) !name_char { return [t, 'text']; }
  / t:( datatype_real ) !name_char { return [t, 'real']; }
  / t:( datatype_numeric ) !name_char { return [t, 'numeric']; }
  / t:( datatype_integer ) !name_char { return [t, 'integer']; }
  / t:( datatype_none ) !name_char { return [t, 'none']; }

datatype_text "TEXT Datatype Name"
  = t:( ( ( "N"i )? ( "VAR"i )? "CHAR"i )
  / ( ( "TINY"i / "MEDIUM"i / "LONG"i )? "TEXT"i )
  / "CLOB"i )
  { return util.key(t); }

datatype_real "REAL Datatype Name"
  = t:( datatype_real_double / "FLOAT"i / "REAL"i )
  { return util.key(t); }

datatype_real_double "DOUBLE Datatype Name"
  = d:( "DOUBLE"i ) p:( [\t ]+ "PRECISION"i )?
  { return util.compose([d, p], ''); }

datatype_numeric "NUMERIC Datatype Name"
  = t:( "NUMERIC"i
  / "DECIMAL"i
  / "BOOLEAN"i
  / ( "DATE"i ( "TIME"i )? )
  / ( "TIME"i ( "STAMP"i )? ) )
  { return util.key(t); }

datatype_integer "INTEGER Datatype Name"
  = t:( ( "INT"i ( "2" / "4" / "8" / "EGER"i ) )
  / ( ( "BIG"i / "MEDIUM"i / "SMALL"i / "TINY"i )? "INT"i ) )
  { return util.key(t); }

datatype_none "BLOB Datatype Name"
  = t:( "BLOB"i )
  { return util.key(t); }

/* Naming rules */

/**
 * @note
 *  This is a best approximation of the characters allowed in an unquoted
 *  identifier or alias.
 */
name_char
  = [a-z0-9\$\_]i

/**
* @note
*  Since SQLite is tolerant of this behavior, although it is non-standard,
*  parser allows single-quoted string literals to be interpreted as aliases.
*/
name
  = name_bracketed
  / name_backticked
  / name_dblquoted
  / name_sglquoted
  / name_unquoted

name_unquoted
  = !( datatype_types / reserved_words / number_digit ) n:( name_char )+
  { return util.key(n); }

/** @note Non-standard legacy format */
name_bracketed
  = sym_bopen n:( !( [ \t]* "]" ) [^\]] )+ o sym_bclose
  { return util.textNode(n); }

name_dblquoted
  = '"' n:( '""' / [^\"] )+ '"'
  { return util.unescape(n, '"'); }

/** @note Non-standard format */
name_sglquoted
  = "'" n:( "''" / [^\'] )+ "'"
  { return util.unescape(n, "'"); }

/** @note Non-standard legacy format */
name_backticked
  = '`' n:( '``' / [^\`] )+ '`'
  { return util.unescape(n, '`'); }

/* Symbols */

sym_bopen "Open Bracket"
  = s:( "[" ) o { return s; }
sym_bclose "Close Bracket"
  = s:( "]" ) o { return s; }
sym_popen "Open Parenthesis"
  = s:( "(" ) o { return s; }
sym_pclose "Close Parenthesis"
  = s:( ")" ) o { return s; }
sym_comma "Comma"
  = s:( "," ) o { return s; }
sym_dot "Period"
  = s:( "." ) o { return s; }
sym_star "Asterisk"
  = s:( "*" ) o { return s; }
sym_quest "Question Mark"
  = s:( "?" ) o { return s; }
sym_sglquote "Single Quote"
  = s:( "'" ) o { return s; }
sym_dblquote "Double Quote"
  = s:( '"' ) o { return s; }
sym_backtick "Backtick"
  = s:( "`" ) o { return s; }
sym_tilde "Tilde"
  = s:( "~" ) o { return s; }
sym_plus "Plus"
  = s:( "+" ) o { return s; }
sym_minus "Minus"
  = s:( "-" ) o { return s; }
sym_equal "Equal"
  = s:( "=" ) o { return s; }
sym_amp "Ampersand"
  = s:( "&" ) o { return s; }
sym_pipe "Pipe"
  = s:( "|" ) o { return s; }
sym_mod "Modulo"
  = s:( "%" ) o { return s; }
sym_lt "Less Than"
  = s:( "<" ) o { return s; }
sym_gt "Greater Than"
  = s:( ">" ) o { return s; }
sym_excl "Exclamation"
  = s:( "!" ) o { return s; }
sym_semi "Semicolon"
  = s:( ";" ) o { return s; }
sym_colon "Colon"
  = s:( ":" ) o { return s; }
sym_fslash "Forward Slash"
  = s:( "/" ) o { return s; }
sym_bslash "Backslash"
  = s:( "\\" ) o { return s; }

/* Keywords */

ABORT
  = "ABORT"i !name_char
ACTION
  = "ACTION"i !name_char
ADD
  = "ADD"i !name_char
AFTER
  = "AFTER"i !name_char
ALL
  = "ALL"i !name_char
ALTER
  = "ALTER"i !name_char
ANALYZE
  = "ANALYZE"i !name_char
AND
  = "AND"i !name_char
AS
  = "AS"i !name_char
ASC
  = "ASC"i !name_char
ATTACH
  = "ATTACH"i !name_char
AUTOINCREMENT
  = "AUTOINCREMENT"i !name_char
BEFORE
  = "BEFORE"i !name_char
BEGIN
  = "BEGIN"i !name_char
BETWEEN
  = "BETWEEN"i !name_char
BY
  = "BY"i !name_char
CASCADE
  = "CASCADE"i !name_char
CASE
  = "CASE"i !name_char
CAST
  = "CAST"i !name_char
CHECK
  = "CHECK"i !name_char
COLLATE
  = "COLLATE"i !name_char
COLUMN
  = "COLUMN"i !name_char
COMMIT
  = "COMMIT"i !name_char
CONFLICT
  = "CONFLICT"i !name_char
CONSTRAINT
  = "CONSTRAINT"i !name_char
CONTAINS
  = "CONTAINS"i !name_char
CREATE
  = "CREATE"i !name_char
CROSS
  = "CROSS"i !name_char
CURRENT_DATE
  = "CURRENT_DATE"i !name_char
CURRENT_TIME
  = "CURRENT_TIME"i !name_char
CURRENT_TIMESTAMP
  = "CURRENT_TIMESTAMP"i !name_char
DATABASE
  = "DATABASE"i !name_char
DEFAULT
  = "DEFAULT"i !name_char
DEFERRABLE
  = "DEFERRABLE"i !name_char
DEFERRED
  = "DEFERRED"i !name_char
DELETE
  = "DELETE"i !name_char
DESC
  = "DESC"i !name_char
DETACH
  = "DETACH"i !name_char
DISTINCT
  = "DISTINCT"i !name_char
DROP
  = "DROP"i !name_char
EACH
  = "EACH"i !name_char
ELSE
  = "ELSE"i !name_char
END
  = "END"i !name_char
ESCAPE
  = "ESCAPE"i !name_char
EXCEPT
  = "EXCEPT"i !name_char
EXCLUSIVE
  = "EXCLUSIVE"i !name_char
EXISTS
  = "EXISTS"i !name_char
EXPLAIN
  = "EXPLAIN"i !name_char
FAIL
  = "FAIL"i !name_char
FOR
  = "FOR"i !name_char
FOREIGN
  = "FOREIGN"i !name_char
FROM
  = "FROM"i !name_char
FULL
  = "FULL"i !name_char
GLOB
  = "GLOB"i !name_char
GROUP
  = "GROUP"i !name_char
HAVING
  = "HAVING"i !name_char
IF
  = "IF"i !name_char
IGNORE
  = "IGNORE"i !name_char
IMMEDIATE
  = "IMMEDIATE"i !name_char
IN
  = "IN"i !name_char
INDEX
  = "INDEX"i !name_char
INDEXED
  = "INDEXED"i !name_char
INITIALLY
  = "INITIALLY"i !name_char
INNER
  = "INNER"i !name_char
INSERT
  = "INSERT"i !name_char
INSTEAD
  = "INSTEAD"i !name_char
INTERSECT
  = "INTERSECT"i !name_char
INTO
  = "INTO"i !name_char
IS
  = "IS"i !name_char
ISNULL
  = "ISNULL"i !name_char
JOIN
  = "JOIN"i !name_char
KEY
  = "KEY"i !name_char
LEFT
  = "LEFT"i !name_char
LIKE
  = "LIKE"i !name_char
LIMIT
  = "LIMIT"i !name_char
MATCH
  = "MATCH"i !name_char
NATURAL
  = "NATURAL"i !name_char
NO
  = "NO"i !name_char
NOT
  = "NOT"i !name_char
NOTNULL
  = "NOTNULL"i !name_char
NULL
  = "NULL"i !name_char
OF
  = "OF"i !name_char
OFFSET
  = "OFFSET"i !name_char
ON
  = "ON"i !name_char
OR
  = "OR"i !name_char
ORDER
  = "ORDER"i !name_char
OUTER
  = "OUTER"i !name_char
PLAN
  = "PLAN"i !name_char
PRAGMA
  = "PRAGMA"i !name_char
PRIMARY
  = "PRIMARY"i !name_char
QUERY
  = "QUERY"i !name_char
RAISE
  = "RAISE"i !name_char
RECURSIVE
  = "RECURSIVE"i !name_char
REFERENCES
  = "REFERENCES"i !name_char
REGEXP
  = "REGEXP"i !name_char
REINDEX
  = "REINDEX"i !name_char
RELEASE
  = "RELEASE"i !name_char
RENAME
  = "RENAME"i !name_char
REPLACE
  = "REPLACE"i !name_char
RESTRICT
  = "RESTRICT"i !name_char
RIGHT
  = "RIGHT"i !name_char
ROLLBACK
  = "ROLLBACK"i !name_char
ROW
  = "ROW"i !name_char
ROWID
  = "ROWID"i !name_char
SAVEPOINT
  = "SAVEPOINT"i !name_char
SELECT
  = "SELECT"i !name_char
SET
  = "SET"i !name_char
TABLE
  = "TABLE"i !name_char
TEMP
  = "TEMP"i !name_char
TEMPORARY
  = "TEMPORARY"i !name_char
THEN
  = "THEN"i !name_char
TO
  = "TO"i !name_char
TRANSACTION
  = "TRANSACTION"i !name_char
TRIGGER
  = "TRIGGER"i !name_char
UNION
  = "UNION"i !name_char
UNIQUE
  = "UNIQUE"i !name_char
UPDATE
  = "UPDATE"i !name_char
USING
  = "USING"i !name_char
VACUUM
  = "VACUUM"i !name_char
VALUES
  = "VALUES"i !name_char
VIEW
  = "VIEW"i !name_char
VIRTUAL
  = "VIRTUAL"i !name_char
WHEN
  = "WHEN"i !name_char
WHERE
  = "WHERE"i !name_char
WITH
  = "WITH"i !name_char
WITHOUT
  = "WITHOUT"i !name_char

reserved_words
  = r:( reserved_word_list )
  { return util.key(r); }

reserved_word_list
  = ABORT / ACTION / ADD / AFTER / ALL / ALTER / ANALYZE / AND / AS /
    ASC / ATTACH / AUTOINCREMENT / BEFORE / BEGIN / BETWEEN / BY /
    CASCADE / CASE / CAST / CHECK / COLLATE / COLUMN / COMMIT /
    CONFLICT / CONSTRAINT / CONTAINS / CREATE / CROSS / CURRENT_DATE /
    CURRENT_TIME / CURRENT_TIMESTAMP / DATABASE / DEFAULT /
    DEFERRABLE / DEFERRED / DELETE / DESC / DETACH / DISTINCT /
    DROP / EACH / ELSE / END / ESCAPE / EXCEPT / EXCLUSIVE / EXISTS /
    EXPLAIN / FAIL / FOR / FOREIGN / FROM / FULL / GLOB / GROUP /
    HAVING / IF / IGNORE / IMMEDIATE / IN / INDEX / INDEXED /
    INITIALLY / INNER / INSERT / INSTEAD / INTERSECT / INTO / IS /
    ISNULL / JOIN / KEY / LEFT / LIKE / LIMIT / MATCH / NATURAL /
    NO / NOT / NOTNULL / NULL / OF / OFFSET / ON / OR / ORDER /
    OUTER / PLAN / PRAGMA / PRIMARY / QUERY / RAISE / RECURSIVE /
    REFERENCES / REGEXP / REINDEX / RELEASE / RENAME / REPLACE /
    RESTRICT / RIGHT / ROLLBACK / ROW / ROWID / SAVEPOINT / SELECT /
    SET / TABLE / TEMP / TEMPORARY / THEN / TO / TRANSACTION /
    TRIGGER / UNION / UNIQUE / UPDATE / USING / VACUUM / VALUES /
    VIEW / VIRTUAL / WHEN / WHERE / WITH / WITHOUT

/* Generic rules */

/* TODO: Not returning anything in AST for comments, should decide what to do with them */
comment
  = comment_line
  / comment_block
  { return null; }

comment_line "Line Comment"
  = "--" ( ![\n\v\f\r] . )*

comment_block "Block Comment"
  = comment_block_start comment_block_feed comment_block_end

comment_block_start
  = "/*"

comment_block_end
  = "*/"

comment_block_body
  = ( !( comment_block_end / comment_block_start ) . )+

block_body_nodes
  = comment_block_body / comment_block

comment_block_feed
  = block_body_nodes ( [\n\v\f\r\t ] / block_body_nodes )*

/* Optional Whitespace */
o "Whitespace"
  = n:( [\n\v\f\r\t ] / comment )*
  { return n; }

/* TODO: Everything with this symbol */
_TODO_
  = "__TODO__"
