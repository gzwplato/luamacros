unit uHttpServer;

{$mode delphi}

interface

uses
  blcksock, sockets, Synautil, Classes, SysUtils;

type

  { THttpServer }

  THttpServer = class (TThread)
    private
      fPort: Integer;
      fHandler: Integer;
      procedure SetPort(AValue: Integer);
    public
      constructor Create(CreateSuspended: Boolean; pPort: Integer; pHandler: Integer);
      property Port: Integer read FPort write SetPort;
    protected
      procedure Execute; override;
      procedure AttendConnection(pSocket: TSocket);
  end;

  { THttpService }

  THttpService = class
    private
      fHttpServer: THttpServer;
    public
      constructor Create;
      destructor Destroy;override;
      procedure StartServer(pPort: Integer; pHandlerRef: Integer);
      procedure StopServer;
  end;


implementation

uses
  uGlobals;

{ THttpServer }

procedure THttpServer.SetPort(AValue: Integer);
begin
  if FPort=AValue then Exit;
  FPort:=AValue;
end;

constructor THttpServer.Create(CreateSuspended: Boolean; pPort: Integer; pHandler: Integer);
begin
  inherited Create(CreateSuspended);
  fPort:= pPort;
  fHandler:= pHandler;
  FreeOnTerminate:=False;
end;

procedure THttpServer.Execute;
var
  ListenerSocket: TTCPBlockSocket;
  ConnectionSocket: TSocket;
begin
  ListenerSocket := TTCPBlockSocket.Create;

  ListenerSocket.CreateSocket;
  ListenerSocket.setLinger(true,10);
  ListenerSocket.bind('0.0.0.0',IntToStr(fPort));
  ListenerSocket.listen;

  repeat
    if ListenerSocket.canread(100) then
    begin
      ConnectionSocket := ListenerSocket.accept;
      AttendConnection(ConnectionSocket);
    end;
  until Terminated;

  ListenerSocket.Free;
end;

procedure THttpServer.AttendConnection(pSocket: TSocket);
var
  timeout: integer;
  s: string;
  method, uri, protocol: string;
  OutputDataString: string;
  ResultCode: integer;
  lSocket: TTCPBlockSocket;
begin
  lSocket := TTCPBlockSocket.Create;
  lSocket.Socket:=pSocket;
  timeout := 120000;

  //read request line
  s := lSocket.RecvString(timeout);
  if (lSocket.LastError <> 0) then
  begin
    //Glb.DebugLog('Socket error: ' + lSocket.LastErrorDesc, cLoggerHtp);
    lSocket.Free;
    exit;
  end;
  if (s = '') then
  begin
    //Glb.DebugLog('No data on socket read', cLoggerHtp);
    lSocket.Free;
    exit;
  end;
  Glb.DebugLog('Incoming request: ' + s, cLoggerHtp);
  method := fetch(s, ' ');
  uri := fetch(s, ' ');
  protocol := fetch(s, ' ');
  //Glb.DebugLog('Received headers+document requesting ' + uri, cLoggerHtp);

  //read request headers
  repeat
    s := lSocket.RecvString(Timeout);
  until s = '';

  // Call LUA code
  Glb.DebugLog(Format('Calling Lua function %d with argument %s.', [fHandler, uri]), cLoggerHtp);
  Glb.LuaEngine.CallFunctionByRef(fHandler, uri);

  // Now write the document to the output stream
    OutputDataString :=
      '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"'
      + ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' + CRLF
      + '<html>OK</html>' + CRLF;

    // Write the headers back to the client
    lSocket.SendString('HTTP/1.0 200' + CRLF);
    lSocket.SendString('Content-type: Text/Html' + CRLF);
    lSocket.SendString('Content-length: ' + IntTostr(Length(OutputDataString)) + CRLF);
    lSocket.SendString('Connection: close' + CRLF);
    lSocket.SendString('Date: ' + Rfc822DateTime(now) + CRLF);
    lSocket.SendString('Server: LuaMacros' + CRLF);
    lSocket.SendString('Access-Control-Allow-Origin: *' + CRLF);
    lSocket.SendString('' + CRLF);

    lSocket.SendString(OutputDataString);
    //ASocket.SendString('HTTP/1.0 404' + CRLF);
    lSocket.Free;
end;


{ THttpService }

constructor THttpService.Create;
begin
  fHttpServer:=nil;
end;

destructor THttpService.Destroy;
begin
  StopServer;
  inherited Destroy;
end;

procedure THttpService.StartServer(pPort: Integer; pHandlerRef: Integer);
begin
  Glb.DebugLogFmt('Starting HTTP server at port %d.', [pPort], cLoggerHtp);
  fHttpServer := THttpServer.Create(true, pPort, pHandlerRef);
  fHttpServer.Start;
end;

procedure THttpService.StopServer;
begin
  if (fHttpServer <> nil) then
  begin
    Glb.DebugLogFmt('Stopping HTTP server at port %d.', [fHttpServer.Port], cLoggerHtp);
    fHttpServer.Terminate;
    fHttpServer.WaitFor;
    fHttpServer.Free;
  end;
end;

end.

