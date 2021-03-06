(*
 *  File:     $RCSfile: OBuffer_Wave.pas,v $
 *  Revision: $Revision: 1.1.1.1 $
 *  Version : $Id: OBuffer_Wave.pas,v 1.1.1.1 2002/04/21 12:57:22 fobmagog Exp $
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
{$DEFINE SEEK_STOP}
unit OBuffer_Wave;

interface
uses
  Windows, SysUtils, MMSystem, Classes, Shared, OBuffer, Player;

type
  TOBuffer_Wave = class(TOBuffer)
  private
    FBufferP: array[0..MAX_CHANNELS-1] of Cardinal;
    FChannels: Cardinal;
    FDataSize: Cardinal;

    FTemp: PByteArray;

    hmmioOut: HMMIO;
    mmioinfoOut: MMIOINFO;
    ckOutRIFF: MMCKINFO;
    ckOut: MMCKINFO;

  public
    constructor Create(NumberOfChannels: Cardinal; Player: TPlayer; Filename: String);
    destructor Destroy; override;

    procedure Append(Channel: Cardinal; Value: SmallInt); override;
    procedure WriteBuffer; override;

{$IFDEF SEEK_STOP}
    procedure ClearBuffer; override;
    procedure SetStopFlag; override;
{$ENDIF}
  end;

function CreateWaveFileOBffer(Player: TPlayer; Filename: String): TOBuffer;

implementation
uses
  Math, Header;

function CreateWaveFileOBffer(Player: TPlayer; Filename: String): TOBuffer;
var Mode: TMode;
    WhichChannels: TChannels;
begin
  Mode := Player.Mode;
  WhichChannels := Player.Channels;
  try
    if ((Mode = SingleChannel) or (WhichChannels <> both)) then
      Result := TOBuffer_Wave.Create(1, Player, Filename)   // mono
    else
      Result := TOBuffer_Wave.Create(2, Player, Filename);  // stereo
  except
    on E: Exception do
      Result := nil;
  end;
end;

{ TOBuffer_Wave }

// Need to break up the 32-bit integer into 2 8-bit bytes.
// (ignore the first two bytes - either 0x0000 or 0xffff)
// Note that Intel byte order is backwards!!!
procedure TOBuffer_Wave.Append(Channel: Cardinal; Value: SmallInt);
begin
  FTemp[FBufferP[Channel]]   := (Value and $ff);
  FTemp[FBufferP[Channel]+1] := (Value shr 8);

  inc(FBufferP[Channel], FChannels shl 1);
end;

procedure TOBuffer_Wave.ClearBuffer;
begin
  // Since we write each frame, and seeks and stops occur between
  // frames, nothing is needed here.
end;

constructor TOBuffer_Wave.Create(NumberOfChannels: Cardinal; Player: TPlayer; Filename: String);
var pwf: TWAVEFORMATEX;
    i: Cardinal;
begin
  FChannels := NumberOfChannels;
  FDataSize := FChannels * OBUFFERSIZE;

  if (Player.Version = MPEG2_LSF) then
    FDataSize := FDataSize shr 1;

  if (Player.Layer = 1) then
    FDataSize := FDataSize div 3;

  FTemp := AllocMem(FDataSize);

  hmmioOut := mmioOpen(PChar(FileName), nil, MMIO_ALLOCBUF or MMIO_WRITE or MMIO_CREATE);
  if (hmmioOut = 0) then
    raise Exception.Create('Output device failure');

  // Create the output file RIFF chunk of form type WAVE.
  ckOutRIFF.fccType := ord('W') or (ord('A') shl 8) or (ord('V') shl 16) or (ord('E') shl 24);
  ckOutRIFF.cksize := 0;
  if (mmioCreateChunk(hmmioOut, @ckOutRIFF, MMIO_CREATERIFF) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Initialize the WAVEFORMATEX structure

  pwf.wBitsPerSample  := 16;  // No 8-bit support yet
  pwf.wFormatTag      := WAVE_FORMAT_PCM;
  pwf.nChannels       := FChannels;
  pwf.nSamplesPerSec  := Player.Frequency;
  pwf.nAvgBytesPerSec := (FChannels * Player.Frequency shl 1);
  pwf.nBlockAlign     := (FChannels shl 1);
  pwf.cbSize          := 0;

  // Create the fmt chunk
  ckOut.ckid := ord('f') or (ord('m') shl 8) or (ord('t') shl 16) or (ord(' ') shl 24);
  ckOut.cksize := sizeof(pwf);

  if (mmioCreateChunk(hmmioOut, @ckOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Write the WAVEFORMATEX structure to the fmt chunk.

  if (mmioWrite(hmmioOut, @pwf, sizeof(pwf)) <> sizeof(pwf)) then
    raise Exception.Create('Output device failure');

  // Ascend out of the fmt chunk, back into the RIFF chunk.
  if (mmioAscend(hmmioOut, @ckOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Create the data chunk that holds the waveform samples.
  ckOut.ckid   := ord('d') or (ord('a') shl 8) or (ord('t') shl 16) or (ord('a') shl 24);
  ckOut.cksize := 0;
  if (mmioCreateChunk(hmmioOut, @ckOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  mmioGetInfo(hmmioOut, @mmioinfoOut, 0);

  for i := 0 to FChannels-1 do
    FBufferP[i] := i * FChannels;
end;

destructor TOBuffer_Wave.Destroy;
begin
  // Mark the current chunk as dirty and flush it
  mmioinfoOut.dwFlags := mmioinfoOut.dwFlags or MMIO_DIRTY;
  if (mmioSetInfo(hmmioOut, @mmioinfoOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Ascend out of data chunk
  if (mmioAscend(hmmioOut, @ckOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Ascend out of RIFF chunk
  if (mmioAscend(hmmioOut, @ckOutRIFF, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Close the file
  if (mmioClose(hmmioOut, 0) <> MMSYSERR_NOERROR) then
    raise Exception.Create('Output device failure');

  // Free the buffer memory
  try
    FreeMem(FTemp);
  except
    on E: Exception do;
  end;
end;

procedure TOBuffer_Wave.SetStopFlag;
begin
end;

procedure TOBuffer_Wave.WriteBuffer;
var Write, i: Cardinal;
begin
  Write := Min(FDataSize, Cardinal(mmioinfoOut.pchEndWrite) - Cardinal(mmioinfoOut.pchNext));

  Move(FTemp^, mmioinfoOut.pchNext^, Write);
  inc(Cardinal(mmioinfoOut.pchNext), Write);

  if (Write < FDataSize) then begin
    mmioinfoOut.dwFlags := mmioinfoOut.dwFlags or MMIO_DIRTY;

    if (mmioAdvance(hmmioOut, @mmioinfoOut, MMIO_WRITE) <> MMSYSERR_NOERROR) then
      raise Exception.Create('Output device failure');
  end;

  Move(FTemp[Write], mmioinfoOut.pchNext^, FDataSize - Write);
  inc(Cardinal(mmioinfoOut.pchNext), FDataSize - Write);

  // Reset buffer pointers
  for i := 0 to FChannels-1 do
    FBufferP[i] := i * FChannels;
end;

end.
