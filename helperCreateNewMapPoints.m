function [mapPoints, vSetKeyFrames, recentPointIdx] = helperCreateNewMapPoints(...
    mapPoints, vSetKeyFrames, currKeyFrameId, intrinsics, scaleFactor, minNumMatches, minParallax)
%helperCreateNewMapPoints creates new map points by triangulating matched 
%   feature points in the current key frame and the connected key frames.
%
%   This is an example helper function that is subject to change or removal 
%   in future releases.

%   Copyright 2019-2020 The MathWorks, Inc.

% Get connected key frames 
KcViews  = connectedViews(vSetKeyFrames, currKeyFrameId, minNumMatches);
KcIDs    = KcViews.ViewId;

% Retreive data of the current key frame
currPose        = vSetKeyFrames.Views.AbsolutePose(currKeyFrameId);
currFeatures    = vSetKeyFrames.Views.Features{currKeyFrameId};
currPoints      = vSetKeyFrames.Views.Points{currKeyFrameId};
currLocations   = currPoints.Location;
currScales      = currPoints.Scale;

% Camera projection matrix
[R1, t1]        = cameraPoseToExtrinsics(currPose.Rotation, currPose.Translation);
currCamMatrix   = cameraMatrix(intrinsics, R1, t1);

recentPointIdx  = [];
for i = 1:numel(KcIDs)
    
    kfPose      = vSetKeyFrames.Views.AbsolutePose(KcIDs(i));
    [kfIndex3d, kfIndex2d] = findWorldPointsInView(mapPoints, KcIDs(i));
    xyzPoints   = mapPoints.WorldPoints(kfIndex3d,:);
    medianDepth = median(vecnorm(xyzPoints - kfPose.Translation, 2, 2));
    
    % Skip the key frame is the change of view is small
    isViewClose = norm(kfPose.Translation - currPose.Translation)/medianDepth < 0.01;
    
    if isViewClose
        continue
    end

    % Retrieve data of the connected key frame
    kfFeatures  = vSetKeyFrames.Views.Features{KcIDs(i)};
    kfPoints    = vSetKeyFrames.Views.Points{KcIDs(i)};
    kfLocations = kfPoints.Location;
    kfScales    = kfPoints.Scale;
    
    % currIndex2d changes in each iteration as new map points are created
    [~, currIndex2d] = findWorldPointsInView(mapPoints, currKeyFrameId);
    
    % Only use unmatched feature points
    uIndices1   = setdiff(uint32(1:size(kfFeatures,1))',  kfIndex2d);
    uIndices2   = setdiff(uint32(1:size(currFeatures,1))', currIndex2d);
    
    uFeatures1  = kfFeatures(uIndices1, :);
    uFeatures2  = currFeatures(uIndices2, :);
    
    uLocations1 = kfLocations(uIndices1, :);
    uLocations2 = currLocations(uIndices2, :);
    
    uScales1    = kfScales(uIndices1);
    uScales2    = currScales(uIndices2);
    
    indexPairs  = matchFeatures(binaryFeatures(uFeatures1), binaryFeatures(uFeatures2),...
        'Unique', true, 'MaxRatio', 0.7, 'MatchThreshold', 40);
    
    if isempty(indexPairs) 
        continue
    end
    
    matchedPoints1 = uLocations1(indexPairs(:,1), :);
    matchedPoints2 = uLocations2(indexPairs(:,2), :);
    
    % Epipole in the current key frame
    epiPole = worldToImage(intrinsics, currPose.Rotation, currPose.Translation, kfPose.Translation);
    distToEpipole = vecnorm(matchedPoints2 - epiPole, 2, 2);
    
    % Compute fundamental matrix
    F = computeF(intrinsics, kfPose, currPose);
    
    % Epipolar line in the second image
    epiLine = epipolarLine(F, matchedPoints2);
    distToLine = abs(sum(epiLine.* [matchedPoints1, ones(size(matchedPoints1,1), 1)], 2))./...
        sqrt(sum(epiLine(:,1:2).^2, 2));
    isValid = distToLine < 2*uScales2(indexPairs(:,2)) & ...
        distToEpipole > 10*uScales2(indexPairs(:,2));
    
    indexPairs = indexPairs(isValid, :);
    matchedPoints1 = matchedPoints1(isValid, :);
    matchedPoints2 = matchedPoints2(isValid, :);
    
    % Parallax check
    isLarge = isLargeParalalx(matchedPoints1, matchedPoints2, kfPose, ...
        currPose, intrinsics, minParallax);

    matchedPoints1  = matchedPoints1(isLarge, :);
    matchedPoints2  = matchedPoints2(isLarge, :);
    indexPairs      = indexPairs(isLarge, :);

    [R2, t2]    = cameraPoseToExtrinsics(kfPose.Rotation, kfPose.Translation);
    kfCamMatrix = cameraMatrix(intrinsics, R2, t2);

    % Triangulate two views to create new world points
    [xyzPoints, reprojectionErrors, validIdx] = triangulate(matchedPoints1, ...
        matchedPoints2, kfCamMatrix, currCamMatrix);

    % Filtering by view direction and reprojection error
    inlier = filterTriangulatedMapPoints(xyzPoints, kfPose, currPose, ...
        uScales1(indexPairs(:,1)), uScales2(indexPairs(:,2)), ...
        reprojectionErrors, scaleFactor, validIdx);

    % Add new map points and update connections 
    if any(inlier)
        xyzPoints   = xyzPoints(inlier,:);
        indexPairs  = indexPairs(inlier, :);
        
        mIndices1   = uIndices1(indexPairs(:, 1));
        mIndices2   = uIndices2(indexPairs(:, 2));
        
        [mapPoints, indices] = addWorldPoints(mapPoints, xyzPoints);
        recentPointIdx       = [recentPointIdx; indices]; %#ok<AGROW>
		
        % Add new observations
        mapPoints  = addCorrespondences(mapPoints, KcIDs(i),indices, mIndices1);
        mapPoints  = addCorrespondences(mapPoints, currKeyFrameId, indices, mIndices2);
        
        % Update connections with new feature matches
        [~,ia]     = intersect(vSetKeyFrames.Connections{:,1:2}, ...
            [KcIDs(i), currKeyFrameId], 'row', 'stable');
        oldMatches = vSetKeyFrames.Connections.Matches{ia};
        newMatches = [oldMatches; mIndices1, mIndices2];
        vSetKeyFrames  = updateConnection(vSetKeyFrames, KcIDs(i), currKeyFrameId, ...
            'Matches', newMatches);
    end
end
end

function F = computeF(intrinsics, pose1, pose2)
R1 = pose1.Rotation';
t1 = pose1.Translation';

R2 = pose2.Rotation';
t2 = pose2.Translation';

R12 = R1'*R2;
t12 = R1'*(t2-t1);

% Skew symmetric matrix
t12x = [0, -t12(3), t12(2)
    t12(3), 0, -t12(1)
    -t12(2) t12(1), 0];
K = intrinsics.IntrinsicMatrix';

F = K'\ t12x * R12 / K;
end

function inlier = filterTriangulatedMapPoints(xyzPoints, pose1, pose2, ...
    scales1, scales2, reprojectionErrors, scaleFactor, isInFront)

camToPoints1= xyzPoints - pose1.Translation;
camToPoints2= xyzPoints - pose2.Translation;

% Check scale consistency and reprojection errors
distances1  = vecnorm(camToPoints1, 2, 2);
distances2  = vecnorm(camToPoints2, 2, 2);
ratioDist   = distances1./distances2;
ratioScale  = scales2./scales1;

ratioFactor = 1.5 * scaleFactor;

isInScale   = (ratioDist./ratioScale < ratioFactor  |  ...
    ratioScale./ratioDist < ratioFactor);

maxError    = sqrt(6);
isSmallError= reprojectionErrors < maxError*min(scales1, scales2);
inlier      = isInScale & isSmallError & isInFront;
end

function isLarge = isLargeParalalx(points1, points2, pose1, pose2, intrinsics, minParallax)

% Parallax check
K = intrinsics.IntrinsicMatrix;
ray1 = [points1, ones(size(points1(:,1)))]/K *pose1.Rotation;
ray2 = [points2, ones(size(points1(:,2)))]/K *pose2.Rotation;

cosParallax = sum(ray1 .* ray2, 2) ./(vecnorm(ray1, 2, 2) .* vecnorm(ray2, 2, 2));
isLarge     = cosParallax < cosd(minParallax) & cosParallax > 0;
end