function [grainID,refInd] = subGrains(Settings,tolerance)
%SUBGRAINS Divide the grains of and EBSD scan  into subgrains
%   [grainID,refInd] = subGrains(Settings,tolerance) returns the vector
%   grainID containing the grain number for each point within the scan such
%   that no point in each grain is more than tolerance degrees from the
%   point refInd within each grain

%Get Quaternion symmetry operators
if length(unique(Settings.Phase)) > 1
    %TODO handle Multi-Phase materials
else
    M = ReadMaterial(Settings.Phase{1});
end
lattype = M.lattice;
if strcmp(lattype,'hexagonal')
    q_symops = rmat2quat(permute(gensymopsHex,[3 2 1]));
else
    q_symops = rmat2quat(permute(gensymops,[3 2 1]));
end

grainID = Settings.grainID;

if min(grainID) == 0
    grainID = grainID + 1;
end
%{
    function newID = getNewRefInd(newGrainIDIn)
        %GETNEWREFIND Find the best reference point for the given grain
        %   Code adapted from GetRefImageInds
        indVec = find(grainID == newGrainIDIn);
        [MaxCI,CIInd] = max(CI(indVec));
        [MinFit,FitInd] = min(Fit(indVec));
        [MaxIQ,IQInd] = max(IQ(indVec));
        
        MaxCITradeoff = Fit(indVec(CIInd))/MinFit + MaxIQ/IQ(indVec(CIInd));
        MinFitTradeOff = MaxIQ/IQ(indVec(FitInd)) + MaxCI/CI(indVec(FitInd));
        MaxIQTradeoff = Fit(indVec(IQInd))/MinFit + MaxCI/CI(indVec(IQInd));
        
        candidates = [CIInd FitInd IQInd];
        
        [~,vote] = min([MaxCITradeoff MinFitTradeOff MaxIQTradeoff]);
        
        newID = indVec(candidates(vote));
    end
%}
%.gif recording stuff for testing, edit doGIF to true to use.
doGIF = false;
if doGIF
    grainIDMap = vec2map(grainID,Settings.Nx,Settings.ScanType);
    figure(314);
    imagesc(grainIDMap);
    axis image
    f = getframe(figure(314));
    [im,map] = rgb2ind(f.cdata,256,'nodither');
end

% The PixleIdxList produced by bwconncomp follows Matlab's matrix indexing
%   style of indexing the entire collumn, then row. OpenXY, howerver, does 
%   the opposite, going row first, then column. This vector is to convert 
%   between the two indexing styles.
IDChangeVec = 1:Settings.ScanLength;
tempMap = vec2map(IDChangeVec',Settings.Ny,Settings.ScanType);
IDChangeVec = map2vec(tempMap');

% Convert the tolerance value to radians, the return type of quatMisoSym
misoThresh = deg2rad(tolerance);


% Find the best refference points for the current grains
refInds = zeros(max(grainID),1);
if isfield(Settings,'RefInd')
    refIndsAll = Settings.grainID;
else
    refIndsAll = grainProcessing.getReferenceInds(Settings);
end
currentGrainNumber = min(grainID);
for ii = currentGrainNumber:length(refInds)
    refInds(ii) = refIndsAll(find(grainID == ii, 1));
end

while currentGrainNumber <= max(grainID)
    % Find the refference point for the current grain and its oreintation
    currentRefInd = refInds(currentGrainNumber);
    referenceOreintation = euler2quat(Settings.Angles(currentRefInd,:));
    
    % Create a logical vector for all the points in the current grain
    currentGrainBool = grainID == currentGrainNumber;
    
    % Get the oreintations of each point
    grainOreintations = euler2quat(Settings.Angles(currentGrainBool,:));
    
    % Find all of the points that are within the threshold misoreintation
    goodPoints = false(Settings.ScanLength,1);
    goodPoints(currentGrainBool) = quatMisoSym(referenceOreintation,grainOreintations,q_symops,'default') < misoThresh;
    
    % Transform the vector into an array to use the bwconncomp function to
    %   find the continuous regions of the points within the threshold
    goodPointsMap = vec2map(goodPoints,Settings.Nx,Settings.ScanType);
    CC = bwconncomp(goodPointsMap,4);
    
    % If there are multiple continuous areas, break them up
    if CC.NumObjects > 1
        changedRefInd = IDChangeVec(currentRefInd);
        for ii = 1:CC.NumObjects
            if ismember(changedRefInd,CC.PixelIdxList{ii})
                % If the area is the part containing the original
                % refference point continue
                break;
            end
        end% ii = 1:CC.NumObjects
        
        % Use the previous loop to find all the new subgrains
        tempInd = find(1:CC.NumObjects ~= ii);
        for jj = tempInd
            % Remove all of the points from the new subgrains
            goodPointsMap(CC.PixelIdxList{jj}) = false;
        end% jj = tempInd
        
        % Transform the map back into a vector
        goodPoints = map2vec(goodPointsMap);
    end% CC.NumObjects > 1
    
    % Create a logical vector corresponding to all of the points not in the
    %   new subgrain that were in the old grain
    newGrainsBool = currentGrainBool & ~goodPoints;
    if any(newGrainsBool)
        % Create another map for bwconncomp to seperate the discontinuous
        %   areas into seperate subgrains
        newGrainsBoolMap = vec2map(newGrainsBool,Settings.Nx,Settings.ScanType);
        CC = bwconncomp(newGrainsBoolMap);
        
        % Seperate the new subgrains by continuity, and find their best
        %   refference points
        if CC.NumObjects > 1
            L = labelmatrix(CC);
            for ii = 1:CC.NumObjects
                newGrainID = max(grainID) + 1;
                grainID(map2vec(L == ii)) = newGrainID;
            refInds(end + 1) = ...
                getRefIndForGrain(Settings, newGrainID, grainID);
            end% ii = 1:CC.NumObjects
        else
            newGrainID = max(grainID) + 1;
            grainID(newGrainsBool) = newGrainID;
            refInds(end + 1) = ...
                getRefIndForGrain(Settings, newGrainID, grainID);
        end% CC.NumObjects > 1
    end% any(newGrainsBool)
    
    currentGrainNumber = currentGrainNumber + 1;
    if doGIF
        imagesc(vec2map(grainID,Settings.Nx,Settings.ScanType));
        axis image
        f = getframe(figure(314));
        im(:,:,1,currentGrainNumber) = rgb2ind(f.cdata,map,'nodither');
    end
end% currentGrainNumber <= max(grainID)
if doGIF
    gifName = 'testing.gif';
    imwrite(im,map,gifName,'DelayTime',0.25,'LoopCount',inf)
end

if nargout >= 2
    refInd = zeros(size(grainID));
    for ii = min(grainID):max(grainID)
        refInd(grainID == ii) = refInds(ii);
    end
end

end

function refInd = getRefIndForGrain(Settings, currentGrainID, grainIDs)

import grainProcessing.refImageInds.*;

if nargin < 3
    grainIDs = Settings.grainID;
end

IQ = Settings.IQ;
CI = Settings.CI;
fit = Settings.Fit;

switch Settings.GrainRefImageType
    case 'Min Kernel Avg Miso'
    case {'IQ > Fit > CI', 'Manual'}
        pointIDs = find(grainIDs == currentGrainID);

        currentCI = CI(pointIDs);
        currentIQ = IQ(pointIDs);
        currentFit = fit(pointIDs);
        pickedPoint = ImageDataBasedGrainRefInd(...
            currentCI, currentIQ, currentFit);
        refInd = pointIDs(pickedPoint);

    case 'Grain Mean Orientation'
    otherwise
        error('OpenXY:UnknownRefImageType',...
            '%s is not a recognized reference image type.',...
            Settings.GrainRefImageType)
end
end

