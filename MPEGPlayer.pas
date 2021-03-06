(*
 *  File:     $RCSfile: MPEGPlayer.pas,v $
 *  Revision: $Revision: 1.1.1.1 $
 *  Version : $Id: MPEGPlayer.pas,v 1.1.1.1 2002/04/21 12:57:22 fobmagog Exp $
 *  Author:   $Author: fobmagog $
 *  Homepage: http://delphimpeg.sourceforge.net/
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *)
unit MPEGPlayer;

interface
uses
  Player, OBuffer, Args, SynthFilter, CRC, Layer3, Shared, Header;

type
  TMPEGPlayer = class(TPlayer)
  private
    FArgs: TMPEGArgs;
    FFilter1: TSynthesisFilter;
    FFilter2: TSynthesisFilter;
    FCRC: TCRC16;
    FOutput: TOBuffer;
    FLayer: Cardinal;
    FLayer3: TLayerIII_Decoder;
    FDoRepeat: Boolean;
    FIsPlaying: Boolean;
    FThreadID: Cardinal;
    FThreadHandle: Cardinal;
    FStartTime: Cardinal;

    function ThreadProc: Cardinal;
    procedure DoDecode;

  protected
    function GetPosition: Integer; override;
    function GetLength: Integer; override;
    function GetMode: TMode; override;
    function GetChannels: TChannels; override;
    function GetVersion: TVersion; override;
    function GetLayer: Integer; override;
    function GetFrequency: Integer; override;
    function GetBitrate: Integer; override;
    function GetIsPlaying: Boolean; override;
    function GetDoRepeat: Boolean; override;
    procedure SetDoRepeat(Value: Boolean); override;

  public
    property Position;
    property Length;
    property Mode;
    property Channels;
    property Version;
    property Layer;
    property Frequency;
    property Bitrate;
    property IsPlaying;
    property DoRepeat;

    constructor Create;
    destructor Destroy; override;

    procedure LoadFile(FileName: String); override;
    procedure SetOutput(Output: TOBuffer); override;
    procedure Play; override;
    procedure Pause; override;
    procedure Stop; override;
  end;

implementation
uses
  Windows, SysUtils, BitStream, SubBand, SubBand1, SubBand2;

function _ThreadProc(Self: TMPEGPlayer): Cardinal; cdecl;
begin
  Result := Self.ThreadProc;
end;

{ TMPEGPlayer }

constructor TMPEGPlayer.Create;
begin
  FArgs := TMPEGArgs.Create;
  FArgs.MPEGHeader := THeader.Create;
  FFilter1 := TSynthesisFilter.Create(0);
  FFilter2 := TSynthesisFilter.Create(1);
  FCRC := nil;
  FOutput := nil;
  FIsPlaying := False;
  FThreadID := 0;
  FThreadHandle := 0;
  FDoRepeat := False;
end;

destructor TMPEGPlayer.Destroy;
begin
  Stop;

  if (Assigned(FCRC)) then
    FreeAndNil(FCRC);

  if (Assigned(FArgs.Stream)) then
    FreeAndNil(FArgs.Stream);

  if (Assigned(FOutput)) then
    FreeAndNil(FOutput);

  FreeAndNil(FFilter1);
  FreeAndNil(FFilter2);
  FreeAndNil(FArgs.MPEGHeader);
  FreeAndNil(FArgs);
end;

procedure TMPEGPlayer.DoDecode;
var Mode: TMode;
    NumSubBands, i: Cardinal;
    SubBands: array[0..31] of TSubBand;
    ReadReady, WriteReady: Boolean;
begin
  // is there a change in important parameters?
  // (bitrate switching is allowed)
  if (FArgs.MPEGHeader.Layer <> FLayer) then begin
    // layer switching is allowed
    if (FArgs.MPEGHeader.Layer = 3) then
      FLayer3 := TLayerIII_Decoder.Create(FArgs.Stream, FArgs.MPEGHeader, FFilter1, FFilter2, FOutput, FArgs.WhichC)
    else if (FLayer = 3) then
      FreeAndNil(FLayer3);

    FLayer := FArgs.MPEGHeader.Layer;
  end;

  if (FLayer <> 3) then begin
    NumSubBands := FArgs.MPEGHeader.NumberOfSubbands;
    Mode := FArgs.MPEGHeader.Mode;

    // create subband objects:
    if (FLayer = 1) then begin
      if (Mode = SingleChannel) then
        for i := 0 to NumSubBands-1 do
          SubBands[i] := TSubbandLayer1.Create(i)
      else if (Mode = JointStereo) then begin
        for i := 0 to FArgs.MPEGHeader.IntensityStereoBound-1 do
          SubBands[i] := TSubbandLayer1Stereo.Create(i);
            
        i := FArgs.MPEGHeader.IntensityStereoBound;
        while (Cardinal(i) < NumSubBands) do begin
          SubBands[i] := TSubbandLayer1IntensityStereo.Create(i);
          inc(i);
        end;
      end else begin
        for i := 0 to NumSubBands-1 do
          SubBands[i] := TSubbandLayer1Stereo.Create(i);
      end;
    end else begin  // Layer II
      if (Mode = SingleChannel) then
        for i := 0 to NumSubBands-1 do
          SubBands[i] := TSubbandLayer2.Create(i)
      else if (Mode = JointStereo) then begin
        for i := 0 to FArgs.MPEGHeader.IntensityStereoBound-1 do
          SubBands[i] := TSubbandLayer2Stereo.Create(i);

        i := FArgs.MPEGHeader.IntensityStereoBound;
        while (Cardinal(i) < NumSubBands) do begin
          SubBands[i] := TSubbandLayer2IntensityStereo.Create(i);
          inc(i);
        end;
      end else begin
        for i := 0 to NumSubBands-1 do
          SubBands[i] := TSubbandLayer2Stereo.Create(i);
      end;
    end;

    // start to read audio data:
    for i := 0 to NumSubBands-1 do
      SubBands[i].ReadAllocation(FArgs.Stream, FArgs.MPEGHeader, FCRC);

    if (FLayer = 2) then
      for i := 0 to NumSubBands-1 do
        TSubBandLayer2(SubBands[i]).ReadScaleFactorSelection(FArgs.Stream, FCRC);

    if (FCRC = nil) or (FArgs.MPEGHeader.ChecksumOK) then begin
      // no checksums or checksum ok, continue reading from stream:
      for i := 0 to NumSubBands-1 do
        SubBands[i].ReadScaleFactor(FArgs.Stream, FArgs.MPEGHeader);

      repeat
        ReadReady := True;
        for i := 0 to NumSubBands-1 do
          ReadReady := SubBands[i].ReadSampleData(FArgs.Stream);

        repeat
          WriteReady := True;
          for i := 0 to NumSubBands-1 do
            WriteReady := SubBands[i].PutNextSample(FArgs.WhichC, FFilter1, FFilter2);

          FFilter1.CalculatePCMSamples(FOutput);
          if ((FArgs.WhichC = Both) and (Mode <> SingleChannel)) then
            FFilter2.CalculatePCMSamples(FOutput);
        until (WriteReady);
      until (ReadReady);

      FOutput.WriteBuffer;
    end;

    for i := 0 to NumSubBands-1 do
      FreeAndNil(SubBands[i]);
  end else  // Layer III
    FLayer3.Decode;
end;

function TMPEGPlayer.GetBitrate: Integer;
begin
  Result := FArgs.MPEGHeader.Bitrate;
end;

function TMPEGPlayer.GetChannels: TChannels;
begin
  Result := FArgs.WhichC;
end;

function TMPEGPlayer.GetDoRepeat: Boolean;
begin
  Result := FDoRepeat;
end;

function TMPEGPlayer.GetFrequency: Integer;
begin
  Result := FArgs.MPEGHeader.Frequency;
end;

function TMPEGPlayer.GetIsPlaying: Boolean;
begin
  Result := FIsPlaying;
end;

function TMPEGPlayer.GetLayer: Integer;
begin
  Result := FArgs.MPEGHeader.Layer;
end;

function TMPEGPlayer.GetLength: Integer;
begin
  Result := Round(FArgs.MPEGHeader.TotalMS(FArgs.Stream) / 1000);
end;

function TMPEGPlayer.GetMode: TMode;
begin
  Result := FArgs.MPEGHeader.Mode;
end;

function TMPEGPlayer.GetPosition: Integer;
begin
  if (FThreadHandle = 0) then
    Result := 0
  else
    Result := (GetTickCount - FStartTime) div 1000;
end;

function TMPEGPlayer.GetVersion: TVersion;
begin
  Result := FArgs.MPEGHeader.Version;
end;

procedure TMPEGPlayer.LoadFile(FileName: String);
begin
  if (Assigned(FCRC)) then
    FreeAndNil(FCRC);

  FArgs.Stream := TBitStream.Create(PChar(FileName));
  FArgs.WhichC := Both;
  FArgs.MPEGHeader.ReadHeader(FArgs.Stream, FCRC);
end;

procedure TMPEGPlayer.Pause;
begin
//  SuspendThread(FThreadHandle);
end;

procedure TMPEGPlayer.Play;
begin
  // Start the thread.
  FIsPlaying := True;
  FThreadHandle := CreateThread(nil, 0, @_ThreadProc, Self, 0, FThreadID);
  if (FThreadHandle = 0) then
    raise Exception.Create('TMPEGPlayer: Thread creation failed.');
  FStartTime := GetTickCount;
end;

procedure TMPEGPlayer.SetDoRepeat(Value: Boolean);
begin
  FDoRepeat := Value;
end;

procedure TMPEGPlayer.SetOutput(Output: TOBuffer);
begin
  FOutput := Output;
end;

procedure TMPEGPlayer.Stop;
begin
  if (FThreadHandle <> 0) then begin
    FIsPlaying := False;
    WaitForSingleObject(FThreadHandle, INFINITE);
    CloseHandle(FThreadHandle);
    FThreadHandle := 0;
  end;
end;

function TMPEGPlayer.ThreadProc: Cardinal;
var FrameRead: Boolean;
    Curr, Total: Cardinal;
begin
  FrameRead := True;
  while (FrameRead) and (FIsPlaying) do begin
    DoDecode;
    FrameRead := FArgs.MPEGHeader.ReadHeader(FArgs.Stream, FCRC);
    Sleep(0);

    Curr := FArgs.Stream.CurrentFrame;
    Total := FArgs.MPEGHeader.MaxNumberOfFrames(FArgs.Stream);

    if (FDoRepeat) then begin
      if ((not FrameRead) and (Curr + 20 >= Total)) or (Curr >= Total) then begin
        FArgs.Stream.Restart;
        if (Assigned(FCRC)) then
          FreeAndNil(FCRC);

        FrameRead := FArgs.MPEGHeader.ReadHeader(FArgs.Stream, FCRC);
      end;

      if (GetTickCount >= FStartTime + Round(FArgs.MPEGHeader.TotalMS(FArgs.Stream))) then
        FStartTime := GetTickCount;
    end;
  end;
  FIsPlaying := False;
  Result := 0;
end;

end.
