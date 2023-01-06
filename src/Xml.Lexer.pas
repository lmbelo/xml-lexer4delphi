(********************************************************
 *                XML Lexer for Delphi                  *
 *                                                      *
 * Copyright (c) 2023 by Lucas Moura Belo - lmbelo      *
 * Licensed under the MIT License                       *
 *                                                      *
 * For full license text and more information visit:    *
 * https://github.com/lmbelo/xml-lexer4delphi           *
 ********************************************************)
unit Xml.Lexer;

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TState = (
    data,
    cdata,
    tagBegin,
    tagName,
    tagEnd,
    attributeNameStart,
    attributeName,
    attributeNameEnd,
    attributeValueBegin,
    attributeValue
  );

  TAction = (
    lt,
    gt,
    space,
    equal,
    quote,
    slash,
    &char,
    error
  );

  TType = (
    text,
    openTag,
    closeTag,
    attributeName,
    attributeValue
  );
  {$SCOPEDENUMS OFF}

  TLexer = class
  public type
    THandler = TProc<char>;
    TEvent = reference to procedure(const AType: TType; const AData: string);
  private type
    TStateMachineActionHandler = array[TAction.lt..TAction.error] of THandler;
    TStateMachine = array[TState.data..TState.attributeValue] of TStateMachineActionHandler;
  private
    FStateMachine: TStateMachine;
  private
    FEvent: TEvent;
    FState: TState;
    FData: string;
    FTagName: string;
    FAttrName: string;
    FAttrValue: string;
    FIsClosing: boolean;
    FOpeningQuote: string;
    procedure Emit(const AType: TType; const AData: string); inline;
  protected
    procedure CreateStateMachine(); virtual;
    procedure Step(const AChar: char); inline;
  public const
    STATE_ACTION_UNREACHABLE = nil;
  public
    constructor Create(const AEvent: TEvent);

    /// <summary>
    ///    Tokenize the characters.
    ///    It supports chuncks of data.
    /// </summary>
    procedure Write(const AXmlData: string);

    property StateMachine: TStateMachine read FStateMachine;
    property State: TState read FState;
    property TagName: string read FTagName;
    property AttrName: string read FAttrname;
    property AttrValue: string read FAttrValue;    
  end;

implementation

uses
  System.Classes;

{ TLexer }

constructor TLexer.Create(const AEvent: TEvent);
begin
  Assert(Assigned(AEvent), 'Invalid argument "AEvent".');
  inherited Create();
  FEvent := AEvent;
  FState := TState.data;
  CreateStateMachine();
end;

procedure TLexer.Emit(const AType: TType; const AData: string);
begin
  // for now, ignore tags like: '?xml', '!DOCTYPE' or comments
  if (FTagName[Low(FTagName)] = '?') or (FTagName[Low(FTagName)] = '!') then
    Exit;

  FEvent(AType, AData);
end;

procedure TLexer.Step(const AChar: char);
var
  LAction: TAction;
begin
  //Default char mappings
  case AChar of
    ' ' : LAction := TAction.space;
    #13 : LAction := TAction.space;
    #10 : LAction := TAction.space;
    #9  : LAction := TAction.space;
    '<' : LAction := TAction.lt;
    '>' : LAction := TAction.gt;
    '"' : LAction := TAction.quote;
    '''': LAction := TAction.quote;
    '=' : LAction := TAction.equal;
    '/' : LAction := TAction.slash;
    else  LAction := TAction.char;
  end;

  //Convert a char to a default action (or char action)
  if (FStateMachine[FState][LAction] <> STATE_ACTION_UNREACHABLE) then
    FStateMachine[FState][LAction](AChar)
  //If the that action state is not reachable, let's see if the error action is reachable
  else if (FStateMachine[FState][TAction.error] <> STATE_ACTION_UNREACHABLE) then
    FStateMachine[FState][TAction.error](AChar)
  //No one else, so let's consider it as a char
  else
    FStateMachine[FState][TAction.char](AChar);
end;

procedure TLexer.Write(const AXmlData: string);
var
  I: Integer;
begin
  for I := Low(AXmlData) to High(AXmlData) do
    Step(AXmlData[I]);
end;

procedure TLexer.CreateStateMachine;
var
  LNoOp: THandler;
var
  LState: TState;
  LAction: TAction;
begin
  for LState := Low(TState) to High(TState) do begin
    for LAction := Low(TAction) to High(TAction) do
      FStateMachine[LState][LAction] := STATE_ACTION_UNREACHABLE;
  end;

  LNoOp := procedure(AChar: char)
  begin
    //
  end;

  //data state
  FStateMachine[TState.data][TAction.lt] := procedure(AChar: char)
  begin
    if not FData.Trim().IsEmpty() then
      Emit(TType.text, FData);
    FTagName := String.Empty;
    FIsClosing := false;
    FState := TState.tagBegin;
  end;

  FStateMachine[TState.data][TAction.char]  := procedure(AChar: char)
  begin
    FData := FData + AChar;
  end;

  //cdata state
  FStateMachine[TState.cdata][TAction.char] := procedure(AChar: char)
  begin
    FData := FData + AChar;
    if FData.EndsWith(']]>') then begin
      Emit(TType.text, FData.SubString(Length(FData) - 3, 3));
      FData := String.Empty;
      FState := TState.data;
    end;
  end;

  //tagBegin state
  FStateMachine[TState.tagBegin][TAction.space] := LNoOp;

  FStateMachine[TState.tagBegin][TAction.char] := procedure(AChar: char)
  begin
    FTagName := AChar;
    FState := TState.tagName;
  end;

  FStateMachine[TState.tagBegin][TAction.slash] := procedure(AChar: char) begin
    FTagName := String.Empty;
    FIsClosing := true;
  end;

  //tagName state
  FStateMachine[TState.tagName][TAction.space] := procedure(AChar: char)
  begin
    if FIsClosing then
      FState := TState.tagEnd
    else begin
      FState := TState.attributeNameStart;
      Emit(TType.openTag, FTagName);
    end;
  end;

  FStateMachine[TState.tagName][TAction.gt] := procedure(AChar: char)
  begin
    if FIsClosing then
      Emit(TType.closeTag, FTagName)
    else
      Emit(TType.openTag, FTagName);

    FData := String.Empty;
    FState := TState.data;
  end;

  FStateMachine[TState.tagName][TAction.slash] := procedure(AChar: char)
  begin
    FState := TState.tagEnd;
    Emit(TType.openTag, FTagName);
  end;

  FStateMachine[TState.tagName][TAction.char] := procedure(AChar: char)
  begin
    FTagName := FTagName + AChar;
    if (FTagName = '![CDATA[') then begin
      FState := TState.cdata;
      FData := String.Empty;
      FTagName := String.Empty;
    end;
  end;

  //tagEnd state
  FStateMachine[TState.tagEnd][TAction.gt] := procedure(AChar: char) begin
    Emit(TType.closeTag, FTagName);
    FData := String.Empty;
    FState := TState.data;
  end;

  FStateMachine[TState.tagEnd][TAction.char] := LNoOp;

  //attributeNameStart state
  FStateMachine[TState.attributeNameStart][TAction.char] := procedure(AChar: char)
  begin
    FAttrName := AChar;
    FState := TState.attributeName;
  end;

  FStateMachine[TState.attributeNameStart][TAction.gt] :=  procedure(AChar: char)
  begin
    FData := String.Empty;
    FState := TState.data;
  end;
  FStateMachine[TState.attributeNameStart][TAction.space] := LNoOp;

  FStateMachine[TState.attributeNameStart][TAction.slash] := procedure(AChar: char)
  begin
    FIsClosing := true;
    FState := TState.tagEnd;
  end;

  //attributeName state
  FStateMachine[TState.attributeName][TAction.space] := procedure(AChar: char)
  begin
    FState := TState.attributeNameEnd;
  end;

  FStateMachine[TState.attributeName][TAction.equal] := procedure(AChar: char)
  begin
    Emit(TType.attributeName, FAttrName);
    FState := TState.attributeValueBegin;
  end;

  FStateMachine[TState.attributeName][TAction.gt] := procedure(AChar: char)
  begin
    FAttrValue := String.Empty;
    Emit(TType.attributeName, FAttrName);
    Emit(TType.attributeValue, FAttrValue);
    FData := String.Empty;
    FState := TState.data;
  end;

  FStateMachine[TState.attributeName][TAction.slash] := procedure(AChar: char)
  begin
    FIsClosing := true;
    FAttrValue := String.Empty;
    Emit(TType.attributeName, FAttrName);
    Emit(TType.attributeValue, FAttrValue);
    FState := TState.tagEnd;
  end;

  FStateMachine[TState.attributeName][TAction.char] := procedure(AChar: char)
  begin
    FAttrName := FAttrName + AChar;
  end;

  //attributeNameEnd state
  FStateMachine[TState.attributeNameEnd][TAction.space] := LNoOp;

  FStateMachine[TState.attributeNameEnd][TAction.equal] := procedure(AChar: char)
  begin
    Emit(TType.attributeName, FAttrName);
    FState := TState.attributeValueBegin;
  end;

  FStateMachine[TState.attributeNameEnd][TAction.gt] := procedure(AChar: char)
  begin
    FAttrValue := String.Empty;
    Emit(TType.attributeName, FAttrName);
    Emit(TType.attributeValue, FAttrValue);
    FData := String.Empty;
    FState := TState.data;
  end;

  FStateMachine[TState.attributeNameEnd][TAction.char] := procedure(AChar: char)
  begin
    FAttrValue := String.Empty;
    Emit(TType.attributeName, FAttrName);
    Emit(TType.attributeValue, FAttrValue);
    FAttrName := AChar;
    FState := TState.attributeName;
  end;

  //attributeValueBegin state
  FStateMachine[TState.attributeValueBegin][TAction.space] := LNoop;

  FStateMachine[TState.attributeValueBegin][TAction.quote] := procedure(AChar: char)
  begin
    FOpeningQuote := AChar;
    FAttrValue := String.Empty;
    FState := TState.attributeValue;
  end;

  FStateMachine[TState.attributeValueBegin][TAction.gt] := procedure(AChar: char)
  begin
    FAttrValue := String.Empty;
    Emit(TType.attributeValue, FAttrValue);
    FData := String.Empty;
    FState := TState.data;
  end;

  FStateMachine[TState.attributeValueBegin][TAction.char] := procedure(AChar: char)
  begin
    FOpeningQuote := String.Empty;
    FAttrValue := AChar;
    FState := TState.attributeValue;
  end;

  //attributeValue state
  FStateMachine[TState.attributeValue][TAction.space] := procedure(AChar: char)
  begin
    if not FOpeningQuote.IsEmpty() then
      FAttrValue := FAttrValue + AChar
    else begin
      Emit(TType.attributeValue, FAttrValue);
      FState := TState.attributeNameStart;
    end;
  end;

  FStateMachine[TState.attributeValue][TAction.quote] := procedure(AChar: char)
  begin
    if (FOpeningQuote = AChar) then begin
      Emit(TType.attributeValue, FAttrValue);
      FState := TState.attributeNameStart;
    end else
      FAttrValue := FAttrValue + AChar;
  end;

  FStateMachine[TState.attributeValue][TAction.gt] := procedure(AChar: char)
  begin
    if not FOpeningQuote.IsEmpty() then
      FAttrValue := FAttrValue + AChar
    else begin
      Emit(TType.attributeValue, FAttrValue);
      FData := String.Empty;
      FState := TState.data;
    end;
  end;

  FStateMachine[TState.attributeValue][TAction.slash] := procedure(AChar: char)
  begin
    if not FOpeningQuote.IsEmpty() then
      FAttrValue := FAttrValue + AChar
    else begin
      Emit(TType.attributeValue, FAttrValue);
      FIsClosing := true;
      FState := TState.tagEnd;
    end;
  end;

  FStateMachine[TState.attributeValue][TAction.char] := procedure(AChar: char)
  begin
    FAttrValue := FAttrValue + AChar;
  end;
end;

end.
