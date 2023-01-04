unit Xml.Lexer;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

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
    TActionHandler = TProc<char>;
    TEvent = TProc<TType, string>;
    TActionPair = TPair<TAction, TActionHandler>;
    TStateActions = TDictionary<TAction, TActionHandler>;
    TStateMachine = TObjectDictionary<TState, TStateActions>;
  private         
    FEvent: TEvent;
    FState: TState;
    FData: string;
    FTagName: string;
    FAttrName: string;
    FAttrValue: string;
    FIsClosing: boolean;
    FOpeningQuote: string;
    FStateMachine: TStateMachine;
    procedure Emit(const AType: TType; const AData: string);
  protected
    procedure CreateStateMachine(); virtual;
    procedure Step(const AChar: char);
  public
    constructor Create(const AEvent: TEvent);
    destructor Destroy(); override;

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

type
  TCharHelper = record helper for char
  public
    function ToAction(): TAction;
  end;

{ TCharHelper }

function TCharHelper.ToAction: TAction;
begin
  case Self of
    ' ' : Result := TAction.space;
    #13 : Result := TAction.space;
    #10 : Result := TAction.space;
    #9  : Result := TAction.space;
    '<' : Result := TAction.lt;
    '>' : Result := TAction.gt;
    '"' : Result := TAction.quote;
    '''': Result := TAction.quote;
    '=' : Result := TAction.equal;
    '/' : Result := TAction.slash;
    else  Result := TAction.char;
  end;
end;

{ TLexer }

constructor TLexer.Create(const AEvent: TEvent);
begin
  Assert(Assigned(AEvent), 'Invalid argument "AEvent".');
  inherited Create();
  FEvent := AEvent;
  FState := TState.data;
  FStateMachine := TStateMachine.Create([doOwnsValues]);  
  CreateStateMachine();
end;

destructor TLexer.Destroy;
begin
  FStateMachine.Free();
  inherited;
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
  LProc: TActionHandler;
  LActions: TStateActions;
begin
  LActions := FStateMachine.Items[FState];
  if not LActions.TryGetValue(AChar.ToAction(), LProc) then
    if not LActions.TryGetValue(TAction.error, LProc) then
      LActions.TryGetValue(TAction.char, LProc);

  if Assigned(LProc) then
    LProc(AChar);
end;           

procedure TLexer.Write(const AXmlData: string);
var
  I: Integer;
begin
  for I := Low(AXmlData) to High(AXmlData) do
    Step(AXmlData[I]);
end;

procedure TLexer.CreateStateMachine;
begin
  //data state
  FStateMachine.Add(
    TState.data, TStateActions.Create([
      //lt action
      TActionPair.Create(TAction.lt, procedure(AChar: char) begin
        if not FData.Trim().IsEmpty() then
          Emit(TType.text, FData);
        FTagName := String.Empty;
        FIsClosing := false;
        FState := TState.tagBegin;
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FData := FData + AChar;
      end)
    ]));

  //cdata state
  FStateMachine.Add(
    TState.cdata, TStateActions.Create([
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FData := FData + AChar;
        if FData.EndsWith(']]>') then begin
          Emit(TType.text, FData.SubString(Length(FData) - 3, 3));
          FData := String.Empty;
          FState := TState.data;
        end;
      end)
    ]));

  //tagBegin state
  FStateMachine.Add(
    TState.tagBegin, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, nil),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FTagName := AChar;
        FState := TState.tagName;
      end),
      //slash action
      TActionPair.Create(TAction.slash, procedure(AChar: char) begin
        FTagName := String.Empty;
        FIsClosing := true;
      end)
    ]));

  //tagName state
  FStateMachine.Add(
    TState.tagName, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, procedure(AChar: char) begin
        if FIsClosing then
          FState := TState.tagEnd
        else begin
          FState := TState.attributeNameStart;
          Emit(TType.openTag, FTagName);
        end;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        if FIsClosing then
          Emit(TType.closeTag, FTagName)
        else
          Emit(TType.openTag, FTagName);

        FData := String.Empty;
        FState := TState.data;
      end),
      //slash action
      TActionPair.Create(TAction.slash, procedure(AChar: char) begin
        FState := TState.tagEnd;
        Emit(TType.openTag, FTagName);
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FTagName := FTagName + AChar;
        if (FTagName = '![CDATA[') then begin
          FState := TState.cdata;
          FData := String.Empty;
          FTagName := String.Empty;
        end;
      end)
    ]));

  //tagEnd state
  FStateMachine.Add(
    TState.tagEnd, TStateActions.Create([
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        Emit(TType.closeTag, FTagName);
        FData := String.Empty;
        FState := TState.data;
      end),
      TActionPair.Create(TAction.char, nil)
    ]));

  //attributeNameStart state
  FStateMachine.Add(
    TState.attributeNameStart, TStateActions.Create([
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FAttrName := AChar;
        FState := TState.attributeName;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        FData := String.Empty;
        FState := TState.data;
      end),
      //space action
      TActionPair.Create(TAction.space, nil),
      //slash action
      TActionPair.Create(TAction.slash, procedure(AChar: char) begin
        FIsClosing := true;
        FState := TState.tagEnd;
      end)
    ]));

  //attributeName state
  FStateMachine.Add(
    TState.attributeName, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, procedure(AChar: char) begin
        FState := TState.attributeNameEnd;
      end),
      //equal action
      TActionPair.Create(TAction.equal, procedure(AChar: char) begin
        Emit(TType.attributeName, FAttrName);
        FState := TState.attributeValueBegin;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        FAttrValue := String.Empty;
        emit(TType.attributeName, FAttrName);
        emit(TType.attributeValue, FAttrValue);
        FData := String.Empty;
        FState := TState.data;
      end),
      //slash action
      TActionPair.Create(TAction.slash, procedure(AChar: char) begin
        FIsClosing := true;
        FAttrValue := String.Empty;
        emit(TType.attributeName, FAttrName);
        emit(TType.attributeValue, FAttrValue);
        FState := TState.tagEnd;
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FAttrName := FAttrName + AChar;
      end)
    ]));

  //attributeNameEnd state
  FStateMachine.Add(
    TState.attributeNameEnd, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, nil),
      //equal action
      TActionPair.Create(TAction.equal, procedure(AChar: char) begin
        Emit(TType.attributeName, FAttrName);
        FState := TState.attributeValueBegin;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        FAttrValue := String.Empty;
        emit(TType.attributeName, FAttrName);
        emit(TType.attributeValue, FAttrValue);
        FData := String.Empty;
        FState := TState.data;
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FAttrValue := String.Empty;
        emit(TType.attributeName, FAttrName);
        emit(TType.attributeValue, FAttrValue);
        FAttrName := AChar;
        FState := TState.attributeName;
      end)
    ]));

  //attributeValueBegin state
  FStateMachine.Add(
    TState.attributeValueBegin, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, nil),
      //quote action
      TActionPair.Create(TAction.quote, procedure(AChar: char) begin
        FOpeningQuote := AChar;
        FAttrValue := String.Empty;
        FState := TState.attributeValue;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        FAttrValue := String.Empty;
        Emit(TType.attributeValue, FAttrValue);
        FData := String.Empty;
        FState := TState.data;
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FOpeningQuote := String.Empty;
        FAttrValue := AChar;
        FState := TState.attributeValue;
      end)
    ]));

  //attributeValue state
  FStateMachine.Add(
    TState.attributeValue, TStateActions.Create([
      //space action
      TActionPair.Create(TAction.space, procedure(AChar: char) begin
        if not FOpeningQuote.IsEmpty() then
          FAttrValue := FAttrValue + AChar
        else begin
          Emit(TType.attributeValue, FAttrValue);
          FState := TState.attributeNameStart;
        end;
      end),
      //quote action
      TActionPair.Create(TAction.quote, procedure(AChar: char) begin
        if (FOpeningQuote = AChar) then begin
          Emit(TType.attributeValue, FAttrValue);
          FState := TState.attributeNameStart;
        end else
          FAttrValue := FAttrValue + AChar;
      end),
      //gt action
      TActionPair.Create(TAction.gt, procedure(AChar: char) begin
        if not FOpeningQuote.IsEmpty() then
          FAttrValue := FAttrValue + AChar
        else begin
          Emit(TType.attributeValue, FAttrValue);
          FData := String.Empty;
          FState := TState.data;
        end;
      end),
      //slash action
      TActionPair.Create(TAction.slash, procedure(AChar: char) begin
        if not FOpeningQuote.IsEmpty() then
          FAttrValue := FAttrValue + AChar
        else begin
          emit(TType.attributeValue, FAttrValue);
          FIsClosing := true;
          FState := TState.tagEnd;
        end;
      end),
      //char action
      TActionPair.Create(TAction.char, procedure(AChar: char) begin
        FAttrValue := FAttrValue + AChar;
      end)
    ]));
end;

end.
