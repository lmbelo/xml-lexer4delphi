# xml-lexer4delphi
Simple Delphi Lexer for XML documents

## Features
- Very small and simple! (~400 sloc)
- Cross-platform
- Event driven API (SAX-like)
- Fault tolerant
- Handles CDATA
- Easy to extend and fine tune (state machine is exposed in Lexer instances)

## Examples

### Happy case

```delphi
var LEvent: TEvent := procedure(AType: TType; AData: string)
begin
  // Write to console
end;
  
const xml = '<hello color="blue">'
          + '  <greeting>Hello, world!</greeting>'
          + '</hello>';

var LLexer := TLexer.Create(LEvent);
try
  LLexer.Write(xml);
finally
  LLexer.Free();
end;

/*
Console output:

{ type: 'open-tag', value: 'hello' }
{ type: 'attribute-name', value: 'color' }
{ type: 'attribute-value', value: 'blue' }
{ type: 'open-tag', value: 'greeting' }
{ type: 'data', value: 'Hello, world!' }
{ type: 'close-tag', value: 'greeting' }
{ type: 'close-tag', value: 'hello' }
*/
```
### Chunked processing

```delphi
const chunk1 = '<hello><greet'; // note this
const chunk2 = 'ing>Hello, world!</greeting></hello>';

LLexer := TLexer.Create(LEvent);
try
  LLexer.Write(chunk1);
  LLexer.Write(chunk2);
finally
  LLexer.Free();
end;

/*
Console output:

{ type: 'open-tag', value: 'hello' }
{ type: 'open-tag', value: 'greeting' }
{ type: 'data', value: 'Hello, world!' }
{ type: 'close-tag', value: 'greeting' }
{ type: 'close-tag', value: 'hello' }
*/
```

### Document with errors

```delphi
LLexer := TLexer.Create(LEvent);
try
  LLexer.Write('<<hello">hi</hello attr="value">');
finally
  LLexer.Free();
end;

/*
Console output (note the open-tag value):

{ type: 'open-tag', value: '<hello"' }
{ type: 'data', value: 'hi' }
{ type: 'close-tag', value: 'hello' }
*/
```

### Update state machine to fix document errors

```delphi
LLexer := TLexer.Create(LEvent);
try
  LLexer.StateMachine[TState.tagBegin][TAction.lt] := procedure(AChar: char) 
  begin 
    //
  end;
  LLexer.StateMachine[TState.tagName][TAction.error] := procedure(AChar: char) 
  begin 
    //
  end;

  LLexer.Write('<<hello">hi</hello attr="value">');
finally
  LLexer.Free();
end;

/*
Console output (note the fixed open-tag value):

{ type: 'open-tag', value: 'hello' }
{ type: 'data', value: 'hi' }
{ type: 'close-tag', value: 'hello' }
*/
```

## License

MIT
