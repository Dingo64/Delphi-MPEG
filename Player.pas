(*
 *  File:     $RCSfile: Player.pas,v $
 *  Revision: $Revision: 1.1.1.1 $
 *  Version : $Id: Player.pas,v 1.1.1.1 2002/04/21 12:57:22 fobmagog Exp $
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
unit Player;

interface
uses
  OBuffer, Shared, Header;

type
  TPlayer = class
  protected
    function GetPosition: Integer; virtual; abstract;
    function GetLength: Integer; virtual; abstract;
    function GetMode: TMode; virtual; abstract;
    function GetChannels: TChannels; virtual; abstract;
    function GetVersion: TVersion; virtual; abstract;
    function GetLayer: Integer; virtual; abstract;
    function GetFrequency: Integer; virtual; abstract;
    function GetBitrate: Integer; virtual; abstract;
    function GetIsPlaying: Boolean; virtual; abstract;
    function GetDoRepeat: Boolean; virtual; abstract;
    procedure SetDoRepeat(Value: Boolean); virtual; abstract;

  public
    property Position: Integer read GetPosition;
    property Length: Integer read GetLength;
    property Mode: TMode read GetMode;
    property Channels: TChannels read GetChannels;
    property Version: TVersion read GetVersion;
    property Layer: Integer read GetLayer;
    property Frequency: Integer read GetFrequency;
    property Bitrate: Integer read GetBitrate;
    property IsPlaying: Boolean read GetIsPlaying;
    property DoRepeat: Boolean read GetDoRepeat write SetDoRepeat;

    procedure LoadFile(FileName: String); virtual; abstract;
    procedure SetOutput(Output: TOBuffer); virtual; abstract;
    procedure Play; virtual; abstract;
    procedure Pause; virtual; abstract;
    procedure Stop; virtual; abstract;
  end;

implementation

end.
