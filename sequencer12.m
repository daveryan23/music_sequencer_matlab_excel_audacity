## Copyright (C) 2018 David Ryan
##
## This program is free software; you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {Function File} {@var{retval} =} sequencer12 (@var{input1}, @var{input2})
##
## @seealso{}
## @end deftypefn

## Author: David Ryan
## Created: 2017-04-27


function [retval] = sequencer12(options)

tic;
retval = 'sequencer12 failed';

% Extract input parameters from options struct
inputFilenameStub = getParam(options, 'inputFilenameStub', 'sequencer12_output');
inputDir = getParam(options, 'inputDir', '.');
outputDir = getParam(options, 'outputDir', '.');
fileTag = getParam(options, 'fileTag', '');

% newVariable = getParam(options, 'newField', 'default value');
display(options);

% (Sample map section would have gone here)

maxChannels = 12;    % Current Excel spreadsheet deals with up to 12 channels

% Full paths for input and output
if length(fileTag)
  fileTag = ['-' fileTag];
endif
outputFilenameStub = [inputFilenameStub '-T' num2str(round(100000*now)) fileTag];
inputPathAndFileCSV = [inputDir '/' inputFilenameStub '.csv'];
outputPathAndFileCSV = [outputDir '/' outputFilenameStub '.csv'];
display(['Input file: ' inputPathAndFileCSV]);
display(['Output file: ' outputPathAndFileCSV]);

% Do the import here with error checking
try
  dataImport = csvread(inputPathAndFileCSV);
catch
  % If previous step throws error (e.g. file not available)
  % then exit with error (return 0)
  importResult = 'import failed';
  return
end_try_catch
importResult = ['import succeeded with size ' num2str(size(dataImport))];
display(importResult);

% Some important variables
datarows = size(dataImport,1)-1;
datacols = size(dataImport,2);
vectBlank = zeros(datarows,1);
vectUnit = (1:datarows)';       % Rename? Its 1..N as a column vector

% Get defaults for each sequence variable
vectControl = vectBlank;
vectChannel = vectBlank;
vectLengthBeats = vectBlank;
vectFreqOrParam = vectBlank;
vectFreqInterpType = vectBlank;
vectAmplitudeDB = vectBlank;
vectAmpInterpType = vectBlank+1;       % Default interpolation is linear for amplitude (e.g. constant decay), not zero
vectAmpTiedToPrevBool = vectBlank;
vectAmpEndAtNextBool = vectBlank;
vectStereoPos = vectBlank;
vectStereoInterpType = vectBlank;

% Match import columns to sequence variables
for k=1:datacols
  colID = dataImport(1,k);
  colData = dataImport(2:end,k);
  switch colID
    case 200
      vectControl = colData;
    case 300
      vectChannel = colData;
    case 400
      vectLengthBeats = max(0,colData);  % Later on beats are counted up
    case 500
      vectFreqOrParam = colData;
    case 510
      vectFreqInterpType = colData;
    case 600
      vectAmplitudeDB = colData;
    case 610
      vectAmpInterpType = colData;
    case 620
      vectAmpTiedToPrevBool = colData;
    case 630
      vectAmpEndAtNextBool = colData;
    case 640
      vectNoteLengthMS = colData;
    case 650
      vectNoteLengthPercentMult = colData;
    case 700
      vectStereoPos = colData;
    case 710
      vectStereoInterpType = colData;
    otherwise
      % Column not claimed - ignore
  endswitch
endfor


% Setup default values for main parameters over all channels
sampleRate = 44100;
bitRate = 16;
playAtFullVolume = 0;
padSecondsBefore = 0.05;
padSecondsAfter = 0.2;
beatsPerMinute = 120;
freqMult = 1;
commaChan1Status = 0;
randSample = rand(20000,1);    % Used for waveformRandom sampling

% Custom Filter Table, rows have control=-80
filterIndex = (vectControl==-80);
filterNumberVect = round(abs(vectLengthBeats(filterIndex)));    % Integer, >=0 (filter 0 not used)
filterFreqHzVect = vectFreqOrParam(filterIndex);                % Should generally be in range 1 Hz to 30000 Hz
filterSetpointDB = vectAmplitudeDB(filterIndex);              % Should be within say -120dB to 0dB. Can also do +ve dB to boost in range.
maxFilterNumber = max(filterNumberVect);
filterStoreCell = cell(max(1,maxFilterNumber),1);
for k=1:maxFilterNumber
  thisFilterIndex = (filterNumberVect==k);
  thisFilterMx = [filterFreqHzVect(thisFilterIndex) filterSetpointDB(thisFilterIndex)];
  filterStoreCell{k} = thisFilterMx;
endfor
%%-------
%% DEBUG CUSTOM FILTERS
%display(filterStoreCell);
%tV = 0:0.01:100;
%pMx = voiceStoreCell{end};
%plot(waveformAdditivePartials(tV,pMx));
%return
%%-------

% Custom Voice Table, rows have control=-90
% Use waveType -N to access custom voice N
voiceIndex = (vectControl==-90);
voiceNumberVect = round(abs(vectLengthBeats(voiceIndex)));                % Integer, >=0 (voice 0 not used)
voiceRelFreqVect = vectFreqOrParam(voiceIndex);  % Can be +ve or -ve freq. Or 0 - use a different voice
voiceRelAmpVect = vectAmplitudeDB(voiceIndex);   % Can be +ve or -ve amp. If freq=0 then amp=1 is sawtooth, amp=2 is square (otherwise sine partials)
maxVoiceType = max(voiceNumberVect);
voiceStoreCell = cell(max(1,maxVoiceType),1);
for k=1:maxVoiceType
  thisVoiceIndex = (voiceNumberVect==k);
  thisVoiceMx = [voiceRelFreqVect(thisVoiceIndex) voiceRelAmpVect(thisVoiceIndex)];
  voiceStoreCell{k} = thisVoiceMx;
endfor
%%-------
%% DEBUG CUSTOM VOICES
%display(voiceStoreCell);
%tV = 0:0.01:100;
%pMx = voiceStoreCell{end};
%plot(waveformAdditivePartials(tV,pMx));
%return
%%-------

% Override default values from import data
% Each max(...) finds the LAST place that control = <specified value>
% so assign each variable only once per sequence file.
% -----
% Sample Rate (only certain values will output correctly, including 8000, 22050, 44100)
index0 = max(vectUnit.*(vectControl==100));
if index0>0; sampleRate = vectFreqOrParam(index0); endif
% -----
% Bit Rate (8, 16, 24, 32 only please)
index0 = max(vectUnit.*(vectControl==110));
if index0>0; bitRate = vectFreqOrParam(index0); endif
% -----
% Play channel at full volume? 1 for full volume, blank for (1/channels) volume normalisation
index0 = max(vectUnit.*(vectControl==111));
if index0>0; playAtFullVolume = vectFreqOrParam(index0); endif
% -----
% Seconds of padding (silence) at start of final tracks
index0 = max(vectUnit.*(vectControl==120));
if index0>0; padSecondsBefore = vectFreqOrParam(index0); endif
% -----
% Seconds of padding (silence) at end of final tracks
index0 = max(vectUnit.*(vectControl==121));
if index0>0; padSecondsAfter = vectFreqOrParam(index0); endif
% -----
% Beats per minute (speed of tracks)
index0 = max(vectUnit.*(vectControl==130));
if index0>0; beatsPerMinute = vectFreqOrParam(index0); endif
% -----
% Frequency Multiplier (retunes all tracks)
index0 = max(vectUnit.*(vectControl==180));
if index0>0; freqMult = vectFreqOrParam(index0); endif
% -----
% Channel 1 Comma Status
% 0 to play channel 1 like a standard channel. Other options do not play channel 1.
% -2 to play higher channels with unnormalised commas based on channel 1 values (which should be near to 1)
% -1 to not play channel 1
% >0 to play higher channels with normalised commas, depending on the (decimal) value given here.
index0 = max(vectUnit.*(vectControl==190));
if index0>0; commaChan1Status = vectFreqOrParam(index0); endif
commaFreqVect = 1;     % This will be extended to a long vector later on!

% Calculations based on parameters
padZerosBefore = zeros(round(padSecondsBefore.*sampleRate),1);
padZerosAfter = zeros(round(padSecondsAfter.*sampleRate),1);
sampleZerosBefore = length(padZerosBefore);
sampleZerosAfter = length(padZerosAfter);
beatsPerSecondDecimal = beatsPerMinute/60;
samplesPerBeatDecimal = sampleRate/beatsPerSecondDecimal;

% First channel MAY be for commas
vectChannel = min(maxChannels,max(0,floor(vectChannel)));
channels = max(vectChannel);
if playAtFullVolume > 0
  volumeConst = 1;
else
  volumeConst = 1./channels;
endif

% Loop over the channels
channelsWritten = 0;
for chan1=1:channels

  % EACH CHANNEL IS PROCESSED ENTIRELY SEPARATELY
  % IT IS THE USER'S RESPONSIBILITY TO CHECK
  % THEY ARE SYNCHRONISED!

  channelIndex = (vectChannel==chan1);

  vectControlChan = vectControl(channelIndex);
  %vectChannelChan = vectChannel(channelIndex);
  vectLengthBeatsChan = vectLengthBeats(channelIndex);
  vectFreqOrParamChan = vectFreqOrParam(channelIndex);
  vectFreqInterpTypeChan = vectFreqInterpType(channelIndex);
  vectAmplitudeDBChan = vectAmplitudeDB(channelIndex);
  vectAmpInterpTypeChan = vectAmpInterpType(channelIndex);
  vectAmpTiedToPrevBoolChan = vectAmpTiedToPrevBool(channelIndex);
  vectAmpEndAtNextBoolChan = vectAmpEndAtNextBool(channelIndex);      
  vectNoteLengthMSChan = vectNoteLengthMS(channelIndex);
  vectNoteLengthPercentMultChan = vectNoteLengthPercentMult(channelIndex);
  vectStereoPosChan = vectStereoPos(channelIndex);
  vectStereoInterpTypeChan = vectStereoInterpType(channelIndex);
  % These should all be the same length!
  lenChannel = length(vectControlChan);

  stereoChannel = (0 < sum(abs(vectStereoPosChan)));   % If any dBR values supplied, make stereo track, otherwise mono.

  vectBeatEnd = cumsum(vectLengthBeatsChan);
  vectBeatStart = [0;vectBeatEnd(1:end-1)];
  totalBeatsInChannel = vectBeatEnd(end);

  % Beat 0 maps to sample 1
  % Beat N maps to sample 1 + samplesPerBeat * N

  totalSamples = 1 + ceil(totalBeatsInChannel * samplesPerBeatDecimal);
  sampleFreqVect = zeros(totalSamples,1);
  sampleAmpVect = zeros(totalSamples,1);
  if stereoChannel
    sampleStereoVect = zeros(totalSamples,1);
  endif

  % DEFAULT VALUES for Channel parameters
  % These can be adjusted mid-track by control messages

  % AMPLITUDE PARAMETERS
  % Parameters affecting exponential (for linear interpolation) decay of note
  dBpeakSeconds = 0.02;                         % s - Seconds to stay at peak amplitude
  dBdecayRate = 20;                             % dB/s - amplitude decay rate at ref. freq. - can set to 0 for no decay
  dBdecayRefFreq = 256;                         % Hz - reference frequency (256Hz recommended)
  dBdecayRefIndex = 0.5;                        % Specifies how much quicker freqs higher than ref freq can decay
  % Parameters affecting tremolo
  tremoloPeriodBeats = 3;                       % Default of peak-trough-peak taking 3 beats
  tremoloDepthDB = 1.5;                         % 0 is off. Positive value is max reduction in amplitude DBs
  % NOT YET IMPLEMENTED: tremoloType - currently Sawtooth only - could be Square, Triangle, etc?

  % FREQUENCY PARAMETERS
  noiseSamples = 20;                            % Write noise onto frequency vector for this number of samples (keep it small)

  % FILTERING PARAMETERS
  filterType = 0;         % No filter by default

  % WAVEFORM PARAMETERS
  voiceType = 0;     % Greater than 0 chooses a custom voice, and overrides waveType
  waveType = 1;
  % 0=Sine, 1=Sawtooth, 2=Square, 3=Triangle, 4=Trapezium, 5=5Square, 6=Random

  muteChannel = 0;   % Play channel by default
  notesWritten = 0;
  prevAmpDB = 0;
  prevTremoloPhase = 0;
  for row1=1:lenChannel                % This Row
    row2 = min(lenChannel,row1+1);     % Next Row
    tempWriteNote = 1;                    % Only write a note if this variable stays 1

    % EACH ROW REPRESENTS:
    % 1) A control message (Control<0)
    % 2) A normal note (Control=0)
    % 3) An altered note (Control>0)  (This was mainly Sequencer 10 - from Sequencer 11 onwards its done via extra columns)

    % Note length modifying variables
    tempNoteLengthMS = vectNoteLengthMSChan(row1);
    tempNoteLengthPercentMult = vectNoteLengthPercentMultChan(row1);    
    
    % SETUP VARIABLES FOR THIS NOTE
    % Timing and Sample Length variables
    tempBeatStart = vectBeatStart(row1);
    
    % Amplitude interpolation and control variables
    tempInterpTypeAmp = vectAmpInterpTypeChan(row1);
    tiedNote = (abs(vectAmpTiedToPrevBoolChan(row1))>0.5);       % 0 = untied, 1 = tied
    tiedNoteNext = (abs(vectAmpTiedToPrevBoolChan(row2))>0.5);   % 0 = untied, 1 = tied
    decayingNote = (abs(vectAmpEndAtNextBoolChan(row1))<0.5);    % 0 = interp to next amp, 1 = interp to decayed amp
    
    % Deal with whether there should be an amplitude gap at the end of this note or not
    if or(tiedNoteNext, !decayingNote)
      % Use original note length when the next note is tied to this one,
      % or when this note doesn't decay in amplitude.
      tempBeatEnd = vectBeatEnd(row1);    
    else
      % If this note doesn't tie to or depend on next note,
      % insert a small amplitude gap at end of the note, depending on
      % a couple of factors
      tempBeatsLength = vectLengthBeatsChan(row1);
      if tempNoteLengthMS > 0
        % Positive ms. Note is that amount of ms.
        tempBeatsLength = beatsPerSecondDecimal * (tempNoteLengthMS/1000);
      elseif tempNoteLengthMS < 0
        % Negative ms. Deduct that number of ms from the note.
        tempBeatsLength = max(0, tempBeatsLength - beatsPerSecondDecimal * (-tempNoteLengthMS/1000));
      elseif tempNoteLengthPercentMult > 0
        % Positive percent mult. Multiply by 0% to 100%. (If there is no next note, 110% has an effect)
        tempBeatsLength = tempBeatsLength * (tempNoteLengthPercentMult/100);
      end
      tempBeatEnd = vectBeatStart(row1) + tempBeatsLength;
    endif
    
    sampleStart = 1 + round(tempBeatStart*samplesPerBeatDecimal);
    sampleEnd = 1 + round(tempBeatEnd*samplesPerBeatDecimal);
    sampleRangeVect = (sampleStart:sampleEnd)';
    noteTimeRangeVect = (1/sampleRate).*(sampleRangeVect-sampleStart);
    sampleLength = length(sampleRangeVect);
    noteLengthSeconds = noteTimeRangeVect(end);

    % Frequency variables
    tempFreq = abs(vectFreqOrParamChan(row1));
    tempNextFreq = abs(vectFreqOrParamChan(row2));
    tempInterpTypeFreq = vectFreqInterpTypeChan(row1);

    % Control variables (less important from sequencer11 onwards)
    tempControl = vectControlChan(row1);
    tempParam = vectFreqOrParamChan(row1);
    tempAbsParam = abs(tempParam);

    % Stereo variables
    tempStereoPos = vectStereoPosChan(row1);         % -100 is left, +100 is right
    tempNextStereoPos = vectStereoPosChan(row2);     % Needed for tied notes - stereo position will move!
    tempInterpTypeStereo = vectStereoInterpTypeChan(row1); 

    % AMPLITUDE VARIABLES

    % Decay rate (as power-law function of frequency)
    if dBdecayRefFreq==0
      modifiedDecayRate = 0;
    else
      modifiedDecayRate = dBdecayRate.*((0.01+tempFreq)/dBdecayRefFreq).^dBdecayRefIndex;
    endif

    % Amplitude - deal with variables related to tied notes
    if tiedNote
      % If a tied note, re-use previous tremolo phase, no peak amplitude section
      %prevTremoloPhase = prevTremoloPhase;    % (Do nothing to this!)
      tempPeakSeconds = 0;
      tempNonPeakSeconds = noteLengthSeconds;
    else
      % If an initial note, reset tremolo phase, have a peak amplitude section
      prevTremoloPhase = 0;
      tempPeakSeconds = min(noteLengthSeconds,dBpeakSeconds);
      tempNonPeakSeconds = noteLengthSeconds-tempPeakSeconds;
    endif

    % sampleRangeVect has length sampleLength - need to split into 2
    if noteLengthSeconds>0
      splitPos = round(sampleLength.*(tempPeakSeconds./noteLengthSeconds));
    else
      splitPos = 1;
    endif
    splitPos = max(1,min(sampleLength,splitPos));
    sampleRangePeakVect = sampleRangeVect(1:splitPos);
    sampleRangeNonPeakVect = sampleRangeVect(splitPos:end);
    sampleLengthPeak = length(sampleRangePeakVect);
    sampleLengthNonPeak = length(sampleRangeNonPeakVect);

    % Amplitude - set starting point (of non-peak period)
    ampDBStartFromThisNote = vectAmplitudeDBChan(row1);
    ampDBStartFromPrevNote = prevAmpDB;     % defined on previous loop or before loop
    if tiedNote
      tempAmpDB = ampDBStartFromPrevNote;
    else
      tempAmpDB = ampDBStartFromThisNote;
    endif

    % Amplitude - set ending point
    ampDBEndFromDecay = tempAmpDB - modifiedDecayRate.*tempNonPeakSeconds;
    ampDBEndFromNextNote = vectAmplitudeDBChan(row2);
    if decayingNote
      tempNextAmpDB = ampDBEndFromDecay;
    else
      tempNextAmpDB = ampDBEndFromNextNote;
    endif

    % Handle transient channel control parameters - use either Param or AbsParam
    % Is it a rest?
    if tempControl<0; tempWriteNote=0; endif;   % Any negative control number means note doesn't play
    % Amplitude decay
    if tempControl==-100; dBpeakSeconds=tempAbsParam; endif;
    if tempControl==-101; dBdecayRate=tempParam; endif;        % Allow < 0
    if tempControl==-102; dBdecayRefFreq=tempAbsParam; endif;
    if tempControl==-103; dBdecayRefIndex=tempParam; endif;    % Allow < 0
    % Amplitude tremolo
    if tempControl==-150; tremoloPeriodBeats=tempAbsParam; endif;
    if tempControl==-151; tremoloDepthDB=tempAbsParam; endif;
    % Frequency noise
    if tempControl==-200; noiseSamples=tempAbsParam; endif;

    % Filter selection
    if tempControl==-350; filterType=round(tempAbsParam); endif;
    % Waveform selection
    if tempControl==-450; voiceType=round(tempAbsParam); endif;
    if tempControl==-400; waveType=round(tempAbsParam); endif;
    % Mute Channel (positive value) or play channel (blank or 0)
    if tempControl==-500; muteChannel=tempAbsParam; endif;
    if tempControl==-999; break; endif;                 % Ignore all remaining notes on channel

    if muteChannel > 0
      % Stop writing notes to this channel if a mute instruction received
      % (Go to next channel using 'break')
      break
    endif

    if and(tempWriteNote==1,sampleLength>1,tempFreq>0)
      % Notes are only written if these hold:
      % - not a control row
      % - positive length
      % - positive frequency

      % Write stereo vector
      if stereoChannel
        sampleStereoVect(sampleRangeVect) = interpMethods(sampleLength,tempStereoPos,tempNextStereoPos,tempInterpTypeStereo);
      endif

      % Write frequency vector
      sampleFreqVect(sampleRangeVect) = freqMult.*interpMethods(sampleLength,tempFreq,tempNextFreq,tempInterpTypeFreq);

      % Modify frequency vector to give small noise
      % at start of note by raising frequency for a small number of samples
      % (Don't do this for a range of conditions in and() statement below)
      if and(0<tempFreq,0<noiseSamples,noiseSamples<sampleLength,!tiedNote)
        r0 = (1:noiseSamples)';
        %rand0 = 1 + 3 * rand(length(r0),1);
        rand0 = 2.5;      % Want frequency to be deterministic. Take the average value of rand() here.
        sampleFreqVect(sampleRangeVect(r0)) = rand0.*sampleFreqVect(sampleRangeVect(r0));
      endif

      % Write amplitude vector (peak period)
      if sampleLengthPeak>0
        sampleAmpVect(sampleRangePeakVect) = tempAmpDB;
      endif

      % Write amplitude vector (non-peak period)
      if sampleLengthNonPeak>0
        %% DEBUG
        %display(sampleRangeNonPeakVect);
        %display(size(sampleRangeNonPeakVect));
        %display(sampleLengthNonPeak);
        sampleAmpVect(sampleRangeNonPeakVect) = interpMethods(sampleLengthNonPeak,tempAmpDB,tempNextAmpDB,tempInterpTypeAmp);
      endif

      % Final amplitude (for next note) should
      % take into account time at peak amplitude
      % but ignore tremolo (i.e. take the final amplitude before subtracting tremolo)
      % Take from actual vector, since won't be end value if flat interpolation used.
      prevAmpDB = sampleAmpVect(sampleRangeVect(end));

      % Modify amplitude vector over both periods if there is a tremolo specified
      % If a period specified, subtract tremolo vector from amplitude vector
      tremoloAmpVect = 0;
      if (tremoloPeriodBeats>0)&&(tremoloDepthDB>0)
        % Make tremolo alteration to amplitude vector.
        % Cosine tremolo
        %tremoloAmpVect = tremoloDepthDB .* (0.5 - 0.5 * cos(2*pi*(prevTremoloPhase + (beatsPerSecondDecimal/tremoloPeriodBeats).*noteTimeRangeVect)));
        % Sawtooth tremolo. Standard sawtooth ramps up, this one is inverted to ramp down.
        tremoloAmpVect = tremoloDepthDB .* (0.5 + 0.5 * waveformSawtooth(prevTremoloPhase + (beatsPerSecondDecimal/tremoloPeriodBeats).*noteTimeRangeVect));
        % Store the final phase for reference in the next row/note
        prevTremoloPhase = prevTremoloPhase + (beatsPerSecondDecimal/tremoloPeriodBeats).*noteTimeRangeVect(end);
      endif
      sampleAmpVect(sampleRangeVect) = sampleAmpVect(sampleRangeVect) - tremoloAmpVect;

      % Finished modifying freq, amp, stereo vectors!
      % Increment count of notes written, and go to next row/note
      notesWritten++;
    endif

  endfor

  % Ignore channel if it has no notes
  if notesWritten<1
    % No notes written on this channel - iterate to next channel
    %display(['Channel ' num2str(chan1) ' empty']);
    continue
  endif

  % Ignore channel if a mute instruction received
  %display([chan1 muteChannel]);
  if muteChannel > 0
    continue
  endif

  % Deal with case where channel 1 is comma shift information
  % This causes microtonal retuning in sections
  if chan1==1
    if commaChan1Status==-1
      % Ignore channel 1 if status is -1, continue to next channel
      display('Comma Channel 1 ignored');
      continue
    elseif commaChan1Status==0
      % Make a dummy comma vector here, and process the channel as normal
      commaFreqVect = ones(length(sampleFreqVect),1);
      channelsWritten++;
    else
      % Set the comma vector here.
      % Sometimes the last entry is a zero. Ones should be the default value
      % Shorten it slightly to get rid of this error
      commaMult = 1/sampleFreqVect(1);     % Divide out by first value (which may be freqMult) - relevant for graph
      commaFreqVect = commaMult * sampleFreqVect(1:max(ceil(0.99*length(sampleFreqVect)),end-5));
      if commaChan1Status > 0
        smoothTime = commaChan1Status;                    % Reuse the (decimal) variable as a timescale
        smoothSamples = floor(smoothTime*sampleRate);                    % Number of samples to smooth over
        smoothCommaVect = averageMoving(commaFreqVect,smoothSamples);    % Once - linear smoothing
        smoothCommaVect = averageMoving(smoothCommaVect,smoothSamples);  % Twice - quadratic smoothing
        smoothCommaVect = averageMoving(smoothCommaVect,smoothSamples);  % Thrice - cubic smoothing
        smoothCommaVect = averageMoving(smoothCommaVect,smoothSamples);  % Four
        smoothCommaVect = averageMoving(smoothCommaVect,smoothSamples);  % Five (multiple times improves phasing!)
        % (Its OK to run this lots of times since it only happens once per sequencing run)
        commaFreqVect0 = commaFreqVect;                                  % Unnormalised version for graphing
        commaFreqVect = commaFreqVect./smoothCommaVect;   % Remove the smoothed version for normalised version
        % ------
        % Plot graph of comma data
        timeVect = 1:length(commaFreqVect);
        timeVect = (1/sampleRate)*timeVect(:);
        plot(timeVect,1200.*log(commaFreqVect)./log(2),'b',timeVect,1200*log(smoothCommaVect)./log(2),'g',timeVect,1200.*log(commaFreqVect0)./log(2),'r');
        %plot(timeVect,log(abs(log(commaFreqVect))),'b');
        %display(commaFreqVect0(end-100:end)');
        %return
        % ------
        commaTag = ['NC' num2str(round(1000*commaChan1Status)) 'ms'];
        display(['Comma Channel 1 processed as commas normalised over ' num2str(round(10*commaChan1Status)/10) 's']);
      else
        commaTag = ['UNC'];
        display('Comma Channel 1 processed as un-normalised commas');
      endif
      outputFilenameStub = [outputFilenameStub '-' commaTag];
      % Comma channel now dealt with - continue to next channel
      continue
    endif
  else
    % For higher channels, check comma vector is long enough, extend if necessary
    extendLength = max(0,length(sampleFreqVect)-length(commaFreqVect));
    if extendLength > 0
      % Need to extend the comma vector to the same length. Use its last value to do so.
      commaFreqVect = [commaFreqVect ; commaFreqVect(end).*ones(extendLength,1)];
    endif
    channelsWritten++;
  endif


  % Frequencies now set up
  %plot(sampleFreqVect);

  % sampleAmpVect in relative dB - change to be negative only (0dB = amplitude 1)
  maxAmpDB = max(sampleAmpVect);
  sampleAmpVect = sampleAmpVect - maxAmpDB;  % -infinity to 0 dB now
  sampleAmpVect = 10.^(sampleAmpVect/20);    % pure amplitude now
  %plot(sampleAmpVect);

  % Anywhere frequency is zero, overwrite amplitude with zero
  sampleAmpVect(abs(sampleFreqVect)<0.001) = 0;
  %plot(sampleAmpVect);

  % Integrate frequency to obtain input vector for waveform
  sampleCumulFreqs = cumsum(sampleFreqVect.*commaFreqVect(1:length(sampleFreqVect)))./sampleRate;
  %plot(sampleCumulFreqs);

  % Apply waveform here. Firstly via voiceType, alternatively via waveType
  % First, if there is a valid voiceType then use additive synth via sine/saw/square partials
  if and(0<voiceType,voiceType<=maxVoiceType)
    partialsMx = voiceStoreCell{voiceType};
  else
    partialsMx = zeros(0,1);
  endif
  if and(size(partialsMx,1)>=1,size(partialsMx,2)>=2)
    % Valid voiceType partialsMx - use for additive synth
    waveOutputVect = waveformAdditivePartials(sampleCumulFreqs,partialsMx);
  else
    % voiceType invalid or missing.
    % Alternatively, use waveType to determine which synth to use
    switch waveType
      case 0     % Sine wave
        waveOutputVect = sin((2.*pi).*sampleCumulFreqs);
      case 1     % Sawtooth wave
        waveOutputVect = waveformSawtooth(sampleCumulFreqs);
      case 2     % Square wave
        waveOutputVect = waveformSquare(sampleCumulFreqs);
      case 3     % Triangle wave
        waveOutputVect = waveformTriangle(sampleCumulFreqs);
      case 4     % Trapezium wave (3/4 from triangle to square)
        waveOutputVect = waveformTrapeziumBasic(sampleCumulFreqs);
      case 5     % Modified Square wave with 3rd harmonic series removed
        waveOutputVect = waveform5Square(sampleCumulFreqs);
      case 6     % Square resampling of a random sample, based on input freqs
        waveOutputVect = waveformRandom(sampleCumulFreqs,randSample);
      case 7     % White noise (independent of frequency)
        waveOutputVect = waveformWhiteNoise(sampleCumulFreqs);
      otherwise
        % Use default voice (Case 1 = Sawtooth)
        waveOutputVect = waveformSawtooth(sampleCumulFreqs);
    endswitch
  endif

  % Choose a filter
  if and(1<=filterType,filterType<=maxFilterNumber)
    freqFilterSetpointMx = filterStoreCell{filterType};
  else
    freqFilterSetpointMx = zeros(0,1);
  endif
  % Deal separately with degenerate cases - should be at least 1 row and 2 columns
  if or(size(freqFilterSetpointMx,1)<1,size(freqFilterSetpointMx,2)<2)
    freqFilterSetpointMx = [1 -120; 15 0; sampleRate 0];     % Filter out inaudibly low noise
  endif
  
  clipFilterSetpointMx = [1 0; 100 0; 1000 -10; 2000 -120];  % Prevent amp or stereoamp from clipping
  % Remove high frequency info from amplitude vector
  % to prevent clipping at start and end of notes
  %sampleAmpVect = averageSmooth7point(sampleAmpVect);    % Doesn't remove enough!
  sampleAmpVect = max(0, filterFromSetpoints(sampleAmpVect,sampleRate,clipFilterSetpointMx));
  
  
  if !stereoChannel
    
    % MONO CASE
    stereoText = 'in mono';

    % Apply amplitudes and padding to waveform
    waveOutputVect = [padZerosBefore;sampleAmpVect.*waveOutputVect;padZerosAfter];

    % Do the filter
    waveOutputVect = filterFromSetpoints(waveOutputVect,sampleRate,freqFilterSetpointMx);

    % Fade to zero in padding sections
    % by -80 dB (for 16 bit audio max needed is 96dB)
    waveOutputVect = fadeStartAndEnd(waveOutputVect,sampleZerosBefore,sampleZerosAfter,-80);

  else
    
    % STEREO CASE
    stereoText = 'in stereo';

    % Remove high frequency info from amplitude vector
    % to prevent clipping at start and end of notes
    %sampleStereoVect = averageSmooth7point(sampleStereoVect);    % Doesn't remove enough!
    sampleStereoVect = filterFromSetpoints(sampleStereoVect,sampleRate,clipFilterSetpointMx);
    
    stereoAmpVects = stereoAmplitudeFromPercent(sampleStereoVect);
    % Input is Nx1 vect of stereo positions
    % -100 for L, 0 for M, +100 for R
    % Output is Nx2 matrix of amplitudes in L, R channels
        
    waveOutputVectL = [padZerosBefore;(stereoAmpVects(:,1).*sampleAmpVect).*waveOutputVect;padZerosAfter];
    waveOutputVectL = filterFromSetpoints(waveOutputVectL,sampleRate,freqFilterSetpointMx);
    waveOutputVectL = fadeStartAndEnd(waveOutputVectL,sampleZerosBefore,sampleZerosAfter,-80);

    waveOutputVectR = [padZerosBefore;(stereoAmpVects(:,2).*sampleAmpVect).*waveOutputVect;padZerosAfter];
    waveOutputVectR = filterFromSetpoints(waveOutputVectR,sampleRate,freqFilterSetpointMx);
    waveOutputVectR = fadeStartAndEnd(waveOutputVectR,sampleZerosBefore,sampleZerosAfter,-80);

    waveOutputVect = [waveOutputVectL waveOutputVectR];

  endif

  % Normalise amplitude to either 1 or 1/channels (from volumeConst earlier)
  waveOutputVect = volumeConst.*waveformNormalise(waveOutputVect);

  % Export it to file
  chanText = num2str(chan1);
  if chan1<10
    chanText = ['0' chanText];
  endif
  freqMultText = '';
  if abs(freqMult-1) > 0.00001
    freqMultText = ['-FM' num2str(round(freqMult*1000))];
  endif
  bpmText = '';
  if beatsPerMinute > 10
    bpmText = ['-BPM' num2str(round(beatsPerMinute))];
  endif
  outputPathAndFileWAV = [outputDir '/' outputFilenameStub freqMultText bpmText '-V' chanText '.wav'];
  display([outputPathAndFileWAV " " stereoText]);
  wavwrite(waveOutputVect,sampleRate,bitRate,outputPathAndFileWAV);

endfor

% Plot waveform (on last channel)
% (Suppressed to be able to plot channel 1, the commas, earlier.)
%plot(waveOutputVect);

% Provide suitable output
display(['Time taken: ' num2str(toc) 's']);
retval = 'sequencer12 succeeded';

if channelsWritten>0
  % Make a copy of the CSV input file alongside output WAVs
  copyfile(inputPathAndFileCSV,outputPathAndFileCSV);
endif

endfunction