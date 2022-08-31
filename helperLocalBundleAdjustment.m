function [mapPoints, directionAndDepth, vSetKeyFrames, newPointIdx] = helperLocalBundleAdjustment(mapPoints, ...
    directionAndDepth, vSetKeyFrames, currKeyFrameId, intrinsics, newPointIdx)
%helperLocalBundleAdjustment refine the pose of the current key frame and 
%   the map of the surrrounding scene.
%
%   This is an example helper function that is subject to change or removal 
%   in future releases.

%   Copyright 2019-2020 The MathWorks, Inc.

% Connected key frames of the current key frame
covisViews    = connectedViews(vSetKeyFrames, currKeyFrameId);
covisViewsIds = covisViews.ViewId;

% Identify the fixed key frames that are connected to the connected
% key frames of the current key frame
fixedViewIds  = [];
for i = 1:numel(covisViewsIds)
    if numel(fixedViewIds) > 10
        break
    end
    tempViews = connectedViews(vSetKeyFrames, covisViewsIds(i));
    tempId    = tempViews.ViewId;
    
    for j = 1:numel(tempId)
        if ~ismember(tempId(j), [fixedViewIds; currKeyFrameId; covisViewsIds])
            fixedViewIds = [fixedViewIds; tempId(j)]; %#ok<AGROW>
            if numel(fixedViewIds) > 10
                break
            end
        end
    end
end

% Always fix the first two key frames
fixedViewIds = [fixedViewIds; intersect(covisViewsIds, [1 2])];

refinedKeyFrameIds = [unique([fixedViewIds; covisViewsIds]); currKeyFrameId];

% Indices of map points observed by local key frames
mapPointIdx  = findWorldPointsInView(mapPoints, [covisViewsIds; currKeyFrameId]);
mapPointIdx  = unique(vertcat(mapPointIdx{:}));

% Find point tracks across the local key frames
numPoints    = numel(mapPointIdx);
tracks       = repmat(pointTrack(0,[0 0]),1, numPoints);
[viewIdsAll, featureIdxAll] = findViewsOfWorldPoint(mapPoints, mapPointIdx);
locations    = cellfun(@(x) x.Location, vSetKeyFrames.Views.Points, 'UniformOutput', false);
for k = 1:numPoints  
    % Use intersect to get the correct ViewIds in the tracks as the
    % connections in vSetKeyFrames are not updated during map point culling
    % or bundle adjustment
    [viewIds, ia] = intersect(viewIdsAll{k},refinedKeyFrameIds, 'stable');
    imagePoints   = zeros(numel(ia), 2);
    for i = 1:numel(ia)
        imagePoints(i, :) = locations{viewIds(i)}(featureIdxAll{k}(ia(i)), :);
    end
    tracks(k)     = pointTrack(viewIds, imagePoints);
end

xyzPoints  = mapPoints.WorldPoints(mapPointIdx,:);
camPoses   = poses(vSetKeyFrames, refinedKeyFrameIds);

% Refine local key frames and map points
[refinedPoints, refinedPoses, reprojectionErrors] = bundleAdjustment(...
    xyzPoints, tracks, camPoses, intrinsics, 'FixedViewIDs', fixedViewIds, ...
    'PointsUndistorted', true, 'AbsoluteTolerance', 1e-7,...
    'RelativeTolerance', 1e-16, 'MaxIteration', 100);

maxError   = 6;
isInlier   = reprojectionErrors < maxError;
inlierIdx  = mapPointIdx(isInlier);
outlierIdx = mapPointIdx(~isInlier);

mapPoints = updateWorldPoints(mapPoints, inlierIdx, refinedPoints(isInlier,:));
vSetKeyFrames = updateView(vSetKeyFrames, refinedPoses);
directionAndDepth = update(directionAndDepth, mapPoints, vSetKeyFrames.Views, inlierIdx, false);

newPointIdx = setdiff(newPointIdx, outlierIdx);

% Update map points and key frames
if ~isempty(outlierIdx)
    mapPoints = removeWorldPoints(mapPoints, outlierIdx);
    directionAndDepth = remove(directionAndDepth, outlierIdx);
end

newPointIdx = newPointIdx - arrayfun(@(x) nnz(x>outlierIdx), newPointIdx);
end