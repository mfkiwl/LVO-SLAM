%% Prepare MATLAB workspace
clear all;
clc;
close all force;
%% Global variables

% Asteroid 
global mu n
% 
% % Spacecraft
% global Isp g0 rl rw rh J_scL Cr Sol As nL l MsL

 
%% Monocular Visual Simultaneous Localization and Mapping

% ROSBAG PROCESSING


%  Load required bag here
bag = rosbag('/media/monsterpc/New Volume/Vignesh/OHB_final_repo/Dataset/Rosbags/depot.bag');

% Parse bag for required message topics 
bSel = select(bag,'Topic','/camera1/image_raw');
bSel2 = select(bag,'Topic','/threeD_pcl2');
bSel3 = select(bag,'Topic','/odom');
bSel4 = select(bag,'Topic','/imu');

% Read messages from above parsed bags
msgStructs = readMessages(bSel,'DataFormat','struct');
msgStructs2 = readMessages(bSel2,'DataFormat','struct');
msgStructs3 = readMessages(bSel3,'DataFormat','struct');
msgStructs4 = readMessages(bSel4,'DataFormat','struct');

% Load extracted images from rosbag here
imageFolder     = '/media/monsterpc/New Volume/Vignesh/OHB_final_repo/Dataset/Images/1500m_5hr_images/';
imds          = imageDatastore(imageFolder);

% Inspect the first image
currFrameIdx = 1;
currI = readimage(imds, currFrameIdx);
preframeIdx=currFrameIdx;
himage = imshow(currI);

%% *Map Initialization*
run= true;
isMapInitialized  = false;
reinittt=false;
Finalstore_lidarpts = [];
afterdark=false;
keyframecount=0;
reinit_flag = 0;
% loop counter for storing global camera poses
gcp = 1;
Finalstore_detected_worldPoints = [];
Finalstore_camera_Poses = [];
Finalstore_spacecraft_Poses = [];
afterdark_flag = 0;
persistent_afd_flag = 0;
Odom_data = [];
Finalstore_camera_Poses_afd = [];
True_timestamp = [];
Final_dark_side = [];    
figvid = 1;

%% Declare Operational Parameters

% Asteroid Parameters

 ai = 502;
 bi = 502;
 ci = 438;
 radius_mean = mean([502 502 438]);
 n =   2.28e-04;
 nr =   3.4907e-04;

% %%Astro Const.
% 
% Au = 1.495978707*10^11; % in meters
% 
% %%Asteroid
% 
%     %%Ryugu
%     mu = 30.01;
%     ai = 502;
%     bi = 502;
%     ci = 438;
%     
%     Ixx = 2.881*1e4;
%     Iyy = 2.3649*1e4;
%     Izz = 2.6794*1e4;
%     
%     a = 1.1264*Au;
%     e = 0.20375;
%     rp = 0.963308*Au;
%     n = 2.2867e-04;
%     C20 = -0.05394;
%     C22 = 0.00266;
%     omega_A = n;
% 
% %% Mission Orbit parameters
% 
%     % nr = n;
%     Rd = 1500;
%      nr = (2*pi)/(5*60*60);
%     % nL = [0 0 nr]';
%     %nr  = sqrt(mu/Rd^3); 
%     T_orbit = (2*pi)/nr;
%     R_res = (mu/n^2)^(1/3);
%     w_ast = [0 0 n]';
% 
%    % Time 
%     Ts = 1;   
%     t0 = 0;
%     tf =  T_orbit;
%     dt = Ts;
%     t = t0:Ts:tf;
% 
% %%General Spacecraft
%     Isp =4190;
%     g0 = 9.80655;
%     l = 1.4;
%     w = 1.3;
%     h = 1.1;
%     rl = l/2;
%     rw = w/2;
%     rh = h/2;
%     
%     Cr = 1.2;
%     Sol = 1367;
%     As = w*h;
% 
% 
%     MsL = 30;
%     m = MsL;
%     JzL = (1/12)*MsL*(l^2 + w^2);
%     JyL = (1/12)*MsL*(l^2 + h^2);
%     JxL = (1/12)*MsL*(w^2 + h^2);
%     J_scL = diag([JxL JyL JzL]);
% 
%     RPos_L =  [Rd 1  1]'; 
%     RVel_L = [0 0 0]';
%     x_L = [RPos_L;RVel_L];
%     q0_L_BI = [0 0 0 1]';
%     w0_L_BI = [0 0 0]';
%     A0_L_BI = [q0_L_BI;w0_L_BI];

%% LVO-SLAM parameters

desired_minimum_features = 980;
skip_frames = 19;
reinit_threshold_featurePts = 450;
reinit_thresholdDist = 150;
focalLength = [1910.81; 1910.81];
principalPoint = [512,512];
imageSize      = size(currI,[1 2]);  % in units of pixels
scaleFactor = 1.2;
numLevels   = 5;
minMatches = 250;
ratioThreshold = 0.45;
eulRot_lidar2camera = [0 1.57 -1.57]; % Lidar body frame to NED frame
odom_hz = 10;


%%  LVO-SLAM
    
while run
    start_flag = 0;
    rng(0);

% Create a cameraIntrinsics object to store the camera intrinsic parameters.
 intrinsics     = cameraIntrinsics(focalLength, principalPoint, imageSize);

if ~isMapInitialized

    keyframecount=0;

if afterdark
    fprintf("Spacecraft is in the dark side. LVO-SLAM is paused until enough illumination is available")
    currI = readimage(imds, currFrameIdx);
    [preFeatures, prePoints] = helperDetectAndExtractFeatures(currI, scaleFactor, numLevels);

    lastKeyFrameId = 2;

while length(preFeatures.Features)<desired_minimum_features % Logic to determine if enough features are available to resume vSLAM 

    currFrameIdx = currFrameIdx+skip_frames;
    
    preframeIdx = currFrameIdx;
    currI = readimage(imds, currFrameIdx);

    [preFeatures, prePoints] = helperDetectAndExtractFeatures(currI, scaleFactor, numLevels); 

    firstI       = currI; % Preserve the first frame 

    afterdark=false;

% Synchronize message topics
    time_inquiry = datetime(msgStructs{currFrameIdx}.Header.Stamp.Sec + 10^-9*msgStructs{currFrameIdx}.Header.Stamp.Nsec,'ConvertFrom','posixtime');
    
    for i=1:length(msgStructs3)
        sync_time_odom = datetime(msgStructs3{i}.Header.Stamp.Sec + 10^-9*msgStructs3{i}.Header.Stamp.Nsec,'ConvertFrom','posixtime');
        dur(i)=abs(sync_time_odom-time_inquiry);
    end

    [~,o] = min(dur);
    raw_odomData = msgStructs3{o};
    odom_data.position = [raw_odomData.Pose.Pose.Position.X raw_odomData.Pose.Pose.Position.Y raw_odomData.Pose.Pose.Position.Z]';
    odom_data.orientation = [raw_odomData.Pose.Pose.Orientation.X raw_odomData.Pose.Pose.Orientation.Y raw_odomData.Pose.Pose.Orientation.Z raw_odomData.Pose.Pose.Orientation.W]';
    
    Final_dark_side = [Final_dark_side odom_data.position]; %  Store spacecraft pose in the dark side

    % Visualize spacecraft motion 
    figure(figvid);pcshow(pointCloud(Finalstore_detected_worldPoints(1:3,:)'));plot3(Finalstore_camera_Poses(1,:),Finalstore_camera_Poses(2,:),Finalstore_camera_Poses(3,:),'-rO');plot3(Final_dark_side(1,:),Final_dark_side(2,:),Final_dark_side(3,:),'-bO');xlabel('X(m)');ylabel('Y(m)');zlabel('Z(m)');set(legend('Asteroid Surface Points','Visual Odometry'),'color','white');
    drawnow

end

else
        fprintf("Spacecraft has exited dark side. Resuming LVO-SLAM")

    [preFeatures, prePoints] = helperDetectAndExtractFeatures(currI, scaleFactor, numLevels); 

    currFrameIdx = currFrameIdx + 1;

    firstI       = currI; % Preserve the first frame 
    
end

% Map initialization loop
while ~isMapInitialized && currFrameIdx < numel(imds.Files)

    currI = readimage(imds, currFrameIdx);

    [currFeatures, currPoints] = helperDetectAndExtractFeatures(currI, scaleFactor, numLevels); 
    currFrameIdx;
    currFrameIdx = currFrameIdx + 1;

    % Find putative feature matches
    indexPairs = matchFeatures(preFeatures, currFeatures, 'Unique', true, ...
        'MaxRatio', 0.9, 'MatchThreshold', 95);

    preMatchedPoints  = prePoints(indexPairs(:,1),:);
    currMatchedPoints = currPoints(indexPairs(:,2),:);

    % If not enough matches are found, check the next frame
    if size(indexPairs, 1) < minMatches
        continue
    end
    
    preMatchedPoints  = prePoints(indexPairs(:,1),:);
    currMatchedPoints = currPoints(indexPairs(:,2),:);
    
    % Compute homography and evaluate reconstruction
    [tformH, scoreH, inliersIdxH] = helperComputeHomography(preMatchedPoints, currMatchedPoints);

    % Compute fundamental matrix and evaluate reconstruction
    [tformF, scoreF, inliersIdxF] = helperComputeFundamentalMatrix(preMatchedPoints, currMatchedPoints);
    
    % Select the model based on a heuristic
    ratio = scoreH/(scoreH + scoreF);

    if ratio > ratioThreshold
        inlierTformIdx = inliersIdxH;
        tform          = tformH;
    else
        inlierTformIdx = inliersIdxF;
        tform          = tformF;
    end

    % Computes the camera location up to scale. Use half of the points to reduce computation   

    inlierPrePoints  = preMatchedPoints(inlierTformIdx);
    inlierCurrPoints = currMatchedPoints(inlierTformIdx);
    [relOrient, relLoc, validFraction] = relativeCameraPose(tform, intrinsics, ...
        inlierPrePoints(1:2:end), inlierCurrPoints(1:2:end));
    
    % If not enough inliers are found, move to the next frame
    if validFraction < 0.9 || numel(size(relOrient))==3
        continue
    end
    
        relPose = rigid3d(relOrient, relLoc);
        minParallax =3; % In degrees
        [isValid, xyzWorldPoints, inlierTriangulationIdx] = helperTriangulateTwoFrames(...
            rigid3d, relPose, inlierPrePoints, inlierCurrPoints, intrinsics, minParallax);

    
    if ~isValid
        continue
    end
    
    % Get the original index of features in the two key frames
    indexPairs = indexPairs(inlierTformIdx(inlierTriangulationIdx),:);
    
    isMapInitialized = true;

    % End of map initialization loop
end 

if isMapInitialized

else
    error('Unable to initialize map.')
end

% Create an empty imageviewset object to store key frames
vSetKeyFrames = imageviewset;

% Create an empty worldpointset object to store 3-D map points
mapPointSet   = worldpointset;

% Create a helperViewDirectionAndDepth object to store view direction and depth 
directionAndDepth = helperViewDirectionAndDepth(size(xyzWorldPoints, 1));

% Add the first key frame. Place the camera associated with the first 
% key frame at the origin, oriented along the Z-axis
preViewId     = 1;
vSetKeyFrames = addView(vSetKeyFrames, preViewId, rigid3d, 'Points', prePoints,...
    'Features', preFeatures.Features);

% Add the second key frame
currViewId    = 2;
vSetKeyFrames = addView(vSetKeyFrames, currViewId, relPose, 'Points', currPoints,...
    'Features', currFeatures.Features);

% Add connection between the first and the second key frame
vSetKeyFrames = addConnection(vSetKeyFrames, preViewId, currViewId, relPose, 'Matches', indexPairs);

% Add 3-D map points
[mapPointSet, newPointIdx] = addWorldPoints(mapPointSet, xyzWorldPoints);

% Add observations of the map points
preLocations  = prePoints.Location;
currLocations = currPoints.Location;
preScales     = prePoints.Scale;
currScales    = currPoints.Scale;

% Add image points corresponding to the map points in the first key frame
mapPointSet   = addCorrespondences(mapPointSet, preViewId, newPointIdx, indexPairs(:,1));

% Add image points corresponding to the map points in the second key frame
mapPointSet   = addCorrespondences(mapPointSet, currViewId, newPointIdx, indexPairs(:,2));

time_inquiry = datetime(msgStructs{preframeIdx}.Header.Stamp.Sec + 10^-9*msgStructs{preframeIdx}.Header.Stamp.Nsec,'ConvertFrom','posixtime');

for i=1:length(msgStructs2)
    time_sync_lidarPts = datetime(msgStructs2{i}.Header.Stamp.Sec + 10^-9*msgStructs2{i}.Header.Stamp.Nsec,'ConvertFrom','posixtime');
    dur_pcl(i)=abs(time_sync_lidarPts-time_inquiry);
end

[~,op] = min(dur_pcl);
xyzPoints = rosReadXYZ(msgStructs2{op});
ptCloud = pointCloud(xyzPoints);
rot = eul2rotm(eulRot_lidar2camera,'XYZ');

trans = [0 0 0.1];
rot_t=rot;
tform = rigid3d(rot_t,trans);

[imPts(:,:,1),indices_point_cloud] = projectLidarPointsOnImage(ptCloud,intrinsics,tform);

currFrameIdx11=1;
projection = [imPts(:,1,currFrameIdx11) imPts(:,2,currFrameIdx11)];
projection_indices_point_cloud = indices_point_cloud;

D_test = pdist2(projection,prePoints(indexPairs(:,1)).Location);
[test_val_min,test_indexmin] = min(D_test);

[mm,test_counter]=min(test_val_min);
mappointindex=(indexPairs(:,1)==test_counter);

counter = 1;

store(counter,:) = [test_counter,test_indexmin(test_counter)];
location_lidar_projection(counter,:) = projection(store(counter,2) ,:);
location_lodar_point_cloud_index (counter,:) = projection_indices_point_cloud(store(counter,2));
location_feature(counter,:) = inlierPrePoints.Location( test_counter,:);


    if sum(mappointindex)== 0 % Check if any current matches are present else choose the closest match.

     [val,idx]=   min(abs(double(indexPairs(:,1))-test_counter));
     map_points_image(counter,:) = mapPointSet.WorldPoints(idx,:);
        
    else
        
         map_points_image(counter,:) = mapPointSet.WorldPoints(mappointindex,:);
    end

    lidar_point_frature_based(counter,:) = ptCloud.Location(location_lodar_point_cloud_index (counter),: );
    lidar_point_frature_based_transformed(counter,:) =  (rot'*lidar_point_frature_based(counter,:)')';
    scale1= lidar_point_frature_based_transformed(1,3)/map_points_image(1,3);
    tmp_scale = scale1;

    counter = counter+1;

%% Refine and Visualize the Initial Reconstruction

% Refine the initial reconstruction using bundleAdjustment that optimizes both camera poses and world points to minimize the overall reprojection 
% errors. After the refinement, the attributes of the map points including 3-D 
% locations, view direction, and depth range are updated. 
% Run full bundle adjustment on the first two key frames

tracks       = findTracks(vSetKeyFrames);
cameraPoses  = poses(vSetKeyFrames);

[refinedPoints, refinedAbsPoses] = bundleAdjustment(xyzWorldPoints, tracks, ...
    cameraPoses, intrinsics, 'FixedViewIDs', 1, ...
    'PointsUndistorted', true, 'AbsoluteTolerance', 1e-7,...
    'RelativeTolerance', 1e-15, 'MaxIteration', 100);

% Scale the map and the camera pose using the median depth of map points
medianDepth   = median(vecnorm(refinedPoints.'));
refinedPoints = refinedPoints * scale1; % Scale the refined points 

refinedAbsPoses.AbsolutePose(currViewId).Translation = ...
refinedAbsPoses.AbsolutePose(currViewId).Translation *scale1;
relPose.Translation = relPose.Translation*scale1;

% Update key frames with the refined poses
vSetKeyFrames = updateView(vSetKeyFrames, refinedAbsPoses);
vSetKeyFrames = updateConnection(vSetKeyFrames, preViewId, currViewId, relPose);

% Update map points with the refined positions
mapPointSet   = updateWorldPoints(mapPointSet, newPointIdx, refinedPoints);

% Update view direction and depth 
directionAndDepth = update(directionAndDepth, mapPointSet, vSetKeyFrames.Views, newPointIdx, true);

% Visualize matched features in the current frame
featurePlot   = helperVisualizeMatchedFeatures(currI, currPoints(indexPairs(:,2)));

% ViewId of the current key frame
currKeyFrameId   = currViewId;

% ViewId of the last key frame
lastKeyFrameId   = currViewId;

% ViewId of the reference key frame that has the most co-visible 
% map points with the current key frame
refKeyFrameId    = currViewId;

% Index of the last key frame in the input image sequence
lastKeyFrameIdx  = currFrameIdx - 1; 

% Indices of all the key frames in the input image sequence
addedFramesIdx   = [1; lastKeyFrameIdx];

isLoopClosed     = false;


else

while ~isLoopClosed && currFrameIdx < numel(imds.Files) % Local mapping and Loop closure

    currI = readimage(imds, currFrameIdx);

    [currFeatures, currPoints] = helperDetectAndExtractFeatures(currI, scaleFactor, numLevels);

    % Track the last key frame
    [currPose, mapPointsIdx, featureIdx] = helperTrackLastKeyFrame(mapPointSet, ...
        vSetKeyFrames.Views, currFeatures, currPoints, lastKeyFrameId, intrinsics, scaleFactor);

   store_curtPoints(gcp) = length(currPoints);
    
    if length(currPoints) < reinit_threshold_featurePts
        afterdark=true;
        afterdark_flag=1;
        isMapInitialized=false;
        break
    end

    % Reinitialization condition 
    if keyframecount>1
        if abs(norm(camera_Poses{gcp-1})-norm(odom_data.position)) > reinit_thresholdDist
                isMapInitialized=false;
                reinit_flag = 1; 

                fprintf("Re-Initializing LVO-SLAM")
                break
        end
   end
    

    % Track the local map
  
    [refKeyFrameId, localKeyFrameIds, currPose, mapPointsIdx, featureIdx] = ...
        helperTrackLocalMap(mapPointSet, directionAndDepth, vSetKeyFrames, mapPointsIdx, ...
        featureIdx, currPose, currFeatures, currPoints, intrinsics, scaleFactor, numLevels);
    

    isKeyFrame = helperIsKeyFrame(mapPointSet, refKeyFrameId, lastKeyFrameIdx, ...
        currFrameIdx, mapPointsIdx);
    
    % Visualize matched features
    updatePlot(featurePlot, currI, currPoints(featureIdx));
    
    if ~isKeyFrame
        currFrameIdx = currFrameIdx + 1;
        continue
    end
    
    % Update current key frame ID
    currKeyFrameId  = currKeyFrameId + 1;
    

%%Local Mapping
% Local mapping is performed for every key frame. When a new key frame is determined, 
% add it to the key frames and update the attributes of the map points observed 
% by the new key frame. To ensure that |mapPointSet| contains as few outliers 
% as possible, a valid map point must be observed in at least 3 key frames. 
% 
% New map points are created by triangulating ORB feature points in the current 
% key frame and its connected key frames. For each unmatched feature point in 
% the current key frame, search for a match with other unmatched points in the 
% connected key frames using <docid:vision_ref#bsvbhh1-1 |matchFeatures|>. The 
% local bundle adjustment refines the pose of the current key frame, the poses 
% of connected key frames, and all the map points observed in these key frames.

    % Add the new key frame 
    [mapPointSet, vSetKeyFrames] = helperAddNewKeyFrame(mapPointSet, vSetKeyFrames, ...
        currPose, currFeatures, currPoints, mapPointsIdx, featureIdx, localKeyFrameIds);
    
    % Remove outlier map points that are observed in fewer than 3 key frames
    [mapPointSet, directionAndDepth, mapPointsIdx] = helperCullRecentMapPoints(mapPointSet, ...
        directionAndDepth, mapPointsIdx, newPointIdx);
    
    % Create new map points by triangulation
    minNumMatches = 5;
    minParallax   = 3;
    [mapPointSet, vSetKeyFrames, newPointIdx] = helperCreateNewMapPoints(mapPointSet, vSetKeyFrames, ...
        currKeyFrameId, intrinsics, scaleFactor, minNumMatches, minParallax);
    
    % Update view direction and depth
    directionAndDepth = update(directionAndDepth, mapPointSet, vSetKeyFrames.Views, ...
        [mapPointsIdx; newPointIdx], true);
    
    % Local bundle adjustment
    [mapPointSet, directionAndDepth, vSetKeyFrames, newPointIdx] = helperLocalBundleAdjustment( ...
        mapPointSet, directionAndDepth, vSetKeyFrames, ...
        currKeyFrameId, intrinsics, newPointIdx); 
    
%%
    time_inquiry = datetime(msgStructs{currFrameIdx}.Header.Stamp.Sec + 10^-9*msgStructs{currFrameIdx}.Header.Stamp.Nsec,'ConvertFrom','posixtime');

    for i=1:length(msgStructs3)
        time_sync_odom = datetime(msgStructs3{i}.Header.Stamp.Sec + 10^-9*msgStructs3{i}.Header.Stamp.Nsec,'ConvertFrom','posixtime');
        dur(i)=abs(time_sync_odom-time_inquiry);
    end

    [M,o] = min(dur);
    raw_odomData = msgStructs3{o};

    for i=1:length(msgStructs2)
        time_sync_lidar = datetime(msgStructs2{i}.Header.Stamp.Sec + 10^-9*msgStructs2{i}.Header.Stamp.Nsec,'ConvertFrom','posixtime');
        dur_pcl(i)=abs(time_sync_lidar-time_inquiry);
    end

    [~,op] = min(dur_pcl);
    xyzPoints = rosReadXYZ(msgStructs2{op});
    
    
    odom_data.position = [raw_odomData.Pose.Pose.Position.X raw_odomData.Pose.Pose.Position.Y raw_odomData.Pose.Pose.Position.Z]';
    odom_data.orientation = [raw_odomData.Pose.Pose.Orientation.X raw_odomData.Pose.Pose.Orientation.Y raw_odomData.Pose.Pose.Orientation.Z raw_odomData.Pose.Pose.Orientation.W]';
    
    tmp_pose = vSetKeyFrames.Views(end,2);
    tmp_pose.AbsolutePose.Translation = ((tmp_pose.AbsolutePose.Translation)')';
    
    pose.Rotation{gcp} = tmp_pose.AbsolutePose.Rotation;
        
    for iter_lidarPts = 1: length(xyzPoints(:,1))
        norm_lidarPts(iter_lidarPts) = norm(xyzPoints(iter_lidarPts,:));
        summa_mean = double(mean(norm_lidarPts));
    end
  
%% Rotate VO and FP back to inertial frame to store and plot   
 
    C_OS = eul2rotm([0 -1.57 1.57],'XYZ'); 
    time_stamp(gcp) = odom_hz*double(raw_odomData.Header.Stamp.Sec);

    if afterdark_flag
    
       translation_vector = odom_data.position;
       ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                        -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                            0 0 1];
       bodyFrame_rotated_odom_pos = ast_rotmat*odom_data.position;
       q_SI = odom_data.orientation; 
       R_SI = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);
       R_SI_init = R_SI;
       persistent_afd_flag = 1;
       afterdark_flag =0;
    
    end
 
    if persistent_afd_flag 
        
        if reinit_flag && keyframecount == 0
            q_SI = odom_data.orientation; 
            R_SI = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);
            translation_vector = odom_data.position;
                  ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                                -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                                    0 0 1];
            bodyFrame_rotated_odom_pos = ast_rotmat*odom_data.position;
            
            transformation_camera = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
            transformation_VO = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
            
            R_SI_init = R_SI;
            
            reinit_flag =0;
         
         else
        
            ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                        -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                          0 0 1];
            
            translation_vector = ast_rotmat'*bodyFrame_rotated_odom_pos ;
            
            q_SI = odom_data.orientation; 
            R_SI = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);        
            transformation_camera = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
            transformation_VO = [[R_SI_init*C_OS*tmp_pose.AbsolutePose.Rotation';[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
        end
        
    end
  
    if gcp==1
        ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                    -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                        0 0 1];
        bodyFrame_rotated_odom_pos = ast_rotmat*odom_data.position;
        q_SI = odom_data.orientation; 
        R_SI_init = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);
    end
        
    if persistent_afd_flag == 0 && afterdark_flag ==0 
    
        if reinit_flag && keyframecount == 0 
            q_SI = odom_data.orientation; 
            R_SI = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);
            translation_vector = odom_data.position;
            ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                            -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                                0 0 1];
            bodyFrame_rotated_odom_pos = ast_rotmat*odom_data.position;
            transformation_camera = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
            transformation_VO = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
            R_SI_init = R_SI;
%             simpa = eul2rotm([0 0 3.14],'XYZ');
%             simpa = R_SI*simpa;
            reinit_flag =0;

        else  
                ast_rotmat = [cos((n)*time_stamp(gcp)) sin((n)*time_stamp(gcp)) 0
                            -sin((n)*time_stamp(gcp)) cos((n)*time_stamp(gcp)) 0
                                0 0 1];
                
                translation_vector = ast_rotmat'*bodyFrame_rotated_odom_pos;
                
                q_SI = odom_data.orientation; 
                R_SI = quat2rotm([q_SI(4) q_SI(1) q_SI(2) q_SI(3)]);        
                transformation_camera = [[R_SI*(C_OS);[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]'];
                transformation_VO = [[R_SI_init*C_OS*tmp_pose.AbsolutePose.Rotation';[0 0 0]] [translation_vector(1) translation_vector(2) translation_vector(3) 1]']; 
%                 simpa = eul2rotm([0 0 3.14],'XYZ');
%                 simpa = ast_rotmat'*simpa;
        end
        
    end


   detected_worldPoints{gcp} = transformation_VO*[(mapPointSet.WorldPoints)';ones(1,length((mapPointSet.WorldPoints(:,1))'))]; %%derotate from NED back to spacecraft BF
    
   camera_Poses{gcp} =  transformation_camera*[((tmp_pose.AbsolutePose.Translation)');1]; %% derotate cam poses from optical frame to spacecraft frame
    
   Finalstore_spacecraft_Poses = [Finalstore_spacecraft_Poses odom_data.position];
   Finalstore_detected_worldPoints = [Finalstore_detected_worldPoints detected_worldPoints{gcp}];

if ~persistent_afd_flag

    Finalstore_camera_Poses = [Finalstore_camera_Poses camera_Poses{gcp}];
    figure(figvid);view(75,10);pcshow(pointCloud(Finalstore_detected_worldPoints(1:3,:)'));hold on;plot3(Finalstore_camera_Poses(1,:),Finalstore_camera_Poses(2,:),Finalstore_camera_Poses(3,:),'-rO');xlabel('X(m)');ylabel('Y(m)');zlabel('Z(m)');set(legend('Asteroid Surface Points','Visual Odometry'),'color','white');
    drawnow

else
    Finalstore_camera_Poses_afd = [Finalstore_camera_Poses_afd camera_Poses{gcp}];
    figure(figvid);view(75,10);pcshow(pointCloud(Finalstore_detected_worldPoints(1:3,:)'));plot3(Finalstore_camera_Poses(1,:),Finalstore_camera_Poses(2,:),Finalstore_camera_Poses(3,:),'-rO');plot3(Final_dark_side(1,:),Final_dark_side(2,:),Final_dark_side(3,:),'-bO');plot3(Finalstore_camera_Poses_afd(1,:),Finalstore_camera_Poses_afd(2,:),Finalstore_camera_Poses_afd(3,:),'-rO');xlabel('X(m)');ylabel('Y(m)');zlabel('Z(m)');set(legend('Asteroid Surface Points','Visual Odometry'),'color','white');
    drawnow
end

  
    camPoses    = poses(vSetKeyFrames);
    currPose    = camPoses(end,:) ;% Contains both ViewId and Pose
    vSetKeyFrames.Views.ViewId(end)
    
    % Initialize the loop closure database
    if currKeyFrameId == 3
        % Load the bag of features data created offline
        bofData         = load('bagOfFeaturesData.mat');
    
        % Initialize the place recognition database
        loopCandidates  = [1; 2];
        loopDatabase    = indexImages(subset(imds, loopCandidates), bofData.bof);
        
    % Check loop closure after some key frames have been created    
    elseif currKeyFrameId > 20
        
        % Minimum number of feature matches of loop edges
        loopEdgeNumMatches = 50;
        
        % Detect possible loop closure key frame candidates
        [isDetected, validLoopCandidates] = helperCheckLoopClosure(vSetKeyFrames, currKeyFrameId, ...
            loopDatabase, currI, loopCandidates, loopEdgeNumMatches);
        
        if isDetected 
            % Add loop closure connections
            [isLoopClosed, mapPointSet, vSetKeyFrames] = helperAddLoopConnections(...
                mapPointSet, vSetKeyFrames, validLoopCandidates, currKeyFrameId, ...
                currFeatures, currPoints, loopEdgeNumMatches);
        end
    end
    
    % If no loop closure is detected, add the image into the database
    if ~isLoopClosed
        addImages(loopDatabase,  subset(imds, currFrameIdx), 'Verbose', false);
        loopCandidates= [loopCandidates; currKeyFrameId]; %#ok<AGROW>
    end
    
    % Update IDs and indices
    lastKeyFrameId  = currKeyFrameId;
    lastKeyFrameIdx = currFrameIdx;
    addedFramesIdx  = [addedFramesIdx; currFrameIdx]; %#ok<AGROW>
    currFrameIdx    = currFrameIdx + 1;
    keyframecount=keyframecount+1;

    gcp = gcp+1;


 % End of main loop
end
end
end

% Optimize the poses
minNumMatches      = 30;
[vSetKeyFramesOptim, poseScales] = optimizePoses(vSetKeyFrames, minNumMatches, 'Tolerance', 1e-16);

% Update map points after optimizing the poses
mapPointSet = helperUpdateGlobalMap(mapPointSet, directionAndDepth, ...
    vSetKeyFrames, vSetKeyFramesOptim, poseScales);

updatePlot(mapPlot, vSetKeyFrames, mapPointSet);

% Plot the optimized camera trajectory
optimizedPoses  = poses(vSetKeyFramesOptim);
plotOptimizedTrajectory(mapPlot, optimizedPoses)

% Update legend
showLegend(mapPlot);

%% PLOT 
final_vo = [Finalstore_camera_Poses Finalstore_camera_Poses_afd];
final_pcl = pointCloud(Finalstore_detected_worldPoints(1:3,:)');

afigure(3)
pcshow(final_pcl);hold on
scatter3(final_vo(1,:),final_vo(2,:),final_vo(3,:));hold on 
scatter3(Finalstore_spacecraft_Poses(1,:),Finalstore_spacecraft_Poses(2,:),Finalstore_spacecraft_Poses(3,:)); hold on
scatter3(Final_dark_side(1,:),Final_dark_side(2,:),Final_dark_side(3,:));hold off
xlabel('X(m)')
ylabel('Y(m)');
zlabel('Z(m)');
legend('Asteroid Surface Points','Visual Odometry','Ground truth','IMU Odometry')
 
%% 
% This concludes an overview of how to build a map of an indoor environment 
% and estimate the trajectory of the camera using ORB-SLAM.
%% Supporting Functions
% Short helper functions are included below. Larger function are included in 
% separate files.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperAddLoopConnections.m') 
% |*helperAddLoopConnections*|> add connections between the current keyframe and 
% the valid loop candidate.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperAddNewKeyFrame.m') 
% |*helperAddNewKeyFrame*|> add key frames to the key frame set.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperCheckLoopClosure.m') 
% |*helperCheckLoopClosure*|> detect loop candidates key frames by retrieving 
% visually similar images from the database.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperCreateNewMapPoints.m') 
% |*helperCreateNewMapPoints*|> create new map points by triangulation.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperLocalBundleAdjustment.m') 
% |*helperLocalBundleAdjustment*|> refine the pose of the current key frame and 
% the map of the surrrounding scene.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperSURFFeatureExtractorFunction.m') 
% |*helperSURFFeatureExtractorFunction*|> implements the SURF feature extraction 
% used in bagOfFeatures.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperTrackLastKeyFrame.m') 
% |*helperTrackLastKeyFrame*|> estimate the current camera pose by tracking the 
% last key frame.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperTrackLocalMap.m') 
% |*helperTrackLocalMap*|> refine the current camera pose by tracking the local 
% map.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperViewDirectionAndDepth.m') 
% |*helperViewDirectionAndDepth*|> store the mean view direction and the predicted 
% depth of map points
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperVisualizeMatchedFeatures.m') 
% |*helperVisualizeMatchedFeatures*|> show the matched features in a frame.
% 
% <matlab:openExample('vision/MonocularVisualSimultaneousLocalizationAndMappingExample','supportingFile','helperVisualizeMotionAndStructure.m') 
% |*helperVisualizeMotionAndStructure*|> show map points and camera trajectory.
% 
% |*helperDetectAndExtractFeatures*| detect and extract and ORB features from 
% the image.

function [features, validPoints] = helperDetectAndExtractFeatures(Irgb, ...
    scaleFactor, numLevels, varargin)

numPoints   = 1000;

% In this example, the images are already undistorted. In a general
% workflow, uncomment the following code to undistort the images.
%
% if nargin > 3
%     intrinsics = varargin{1};
% end
% Irgb  = undistortImage(Irgb, intrinsics);

% Detect ORB features
Igray  = im2gray(Irgb);

points = detectORBFeatures(Igray, 'ScaleFactor', scaleFactor, 'NumLevels', numLevels);

% Select a subset of features, uniformly distributed throughout the image
points = selectUniform(points, numPoints, size(Igray, 1:2));

% Extract features
[features, validPoints] = extractFeatures(Igray, points);
end
%% 
% |*helperHomographyScore*| compute homography and evaluate reconstruction.

function [H, score, inliersIndex] = helperComputeHomography(matchedPoints1, matchedPoints2)

[H, inliersLogicalIndex] = estimateGeometricTransform2D( ...
    matchedPoints1, matchedPoints2, 'projective', ...
    'MaxNumTrials', 1e3, 'MaxDistance', 4, 'Confidence', 90);

inlierPoints1 = matchedPoints1(inliersLogicalIndex);
inlierPoints2 = matchedPoints2(inliersLogicalIndex);

inliersIndex  = find(inliersLogicalIndex);

locations1 = inlierPoints1.Location;
locations2 = inlierPoints2.Location;
xy1In2     = transformPointsForward(H, locations1);
xy2In1     = transformPointsInverse(H, locations2);
error1in2  = sum((locations2 - xy1In2).^2, 2);
error2in1  = sum((locations1 - xy2In1).^2, 2);

outlierThreshold = 6;

score = sum(max(outlierThreshold-error1in2, 0)) + ...
    sum(max(outlierThreshold-error2in1, 0));
end
%% 
% |*helperFundamentalMatrixScore*| compute fundamental matrix and evaluate reconstruction.

function [F, score, inliersIndex] = helperComputeFundamentalMatrix(matchedPoints1, matchedPoints2)

[F, inliersLogicalIndex]   = estimateFundamentalMatrix( ...
    matchedPoints1, matchedPoints2, 'Method','RANSAC',...
    'NumTrials', 1e3, 'DistanceThreshold', 0.01);

inlierPoints1 = matchedPoints1(inliersLogicalIndex);
inlierPoints2 = matchedPoints2(inliersLogicalIndex);

inliersIndex  = find(inliersLogicalIndex);

locations1    = inlierPoints1.Location;
locations2    = inlierPoints2.Location;

% Distance from points to epipolar line
lineIn1   = epipolarLine(F', locations2);
error2in1 = (sum([locations1, ones(size(locations1, 1),1)].* lineIn1, 2)).^2 ...
    ./ sum(lineIn1(:,1:2).^2, 2);
lineIn2   = epipolarLine(F, locations1);
error1in2 = (sum([locations2, ones(size(locations2, 1),1)].* lineIn2, 2)).^2 ...
    ./ sum(lineIn2(:,1:2).^2, 2);

outlierThreshold = 4;

score = sum(max(outlierThreshold-error1in2, 0)) + ...
    sum(max(outlierThreshold-error2in1, 0));

end
%% 
% |*helperTriangulateTwoFrames*| triangulate two frames to initialize the map.

function [isValid, xyzPoints, inlierIdx] = helperTriangulateTwoFrames(...
    pose1, pose2, matchedPoints1, matchedPoints2, intrinsics, minParallax)

[R1, t1]   = cameraPoseToExtrinsics(pose1.Rotation, pose1.Translation);
camMatrix1 = cameraMatrix(intrinsics, R1, t1);

[R2, t2]   = cameraPoseToExtrinsics(pose2.Rotation, pose2.Translation);
camMatrix2 = cameraMatrix(intrinsics, R2, t2);

[xyzPoints, reprojectionErrors, isInFront] = triangulate(matchedPoints1, ...
    matchedPoints2, camMatrix1, camMatrix2);

% Filter points by view direction and reprojection error
minReprojError = 1;
inlierIdx  = isInFront & reprojectionErrors < minReprojError;
xyzPoints  = xyzPoints(inlierIdx ,:);

% A good two-view with significant parallax
ray1       = xyzPoints - pose1.Translation;
ray2       = xyzPoints - pose2.Translation;
cosAngle   = sum(ray1 .* ray2, 2) ./ (vecnorm(ray1, 2, 2) .* vecnorm(ray2, 2, 2));

% Check parallax
isValid = all(cosAngle < cosd(minParallax) & cosAngle>0);
end
%% 
% |*helperIsKeyFrame*| check if a frame is a key frame.

function isKeyFrame = helperIsKeyFrame(mapPoints, ...
    refKeyFrameId, lastKeyFrameIndex, currFrameIndex, mapPointsIndices)

numPointsRefKeyFrame = numel(findWorldPointsInView(mapPoints, refKeyFrameId));

% More than 20 frames have passed from last key frame insertion
tooManyNonKeyFrames = currFrameIndex > lastKeyFrameIndex + 19;

% Track less than 100 map points
tooFewMapPoints     = numel(mapPointsIndices) < 100;

% Tracked map points are fewer than 90% of points tracked by
% the reference key frame
tooFewTrackedPoints = numel(mapPointsIndices) < 0.9 * numPointsRefKeyFrame;

isKeyFrame = (tooManyNonKeyFrames || tooFewMapPoints) && tooFewTrackedPoints;
end
%% 
% |*helperCullRecentMapPoints*| cull recently added map points.

function [mapPointSet, directionAndDepth, mapPointsIdx] = helperCullRecentMapPoints(mapPointSet, directionAndDepth, mapPointsIdx, newPointIdx)
outlierIdx    = setdiff(newPointIdx, mapPointsIdx);
if ~isempty(outlierIdx)
    mapPointSet   = removeWorldPoints(mapPointSet, outlierIdx);
    directionAndDepth = remove(directionAndDepth, outlierIdx);
    mapPointsIdx  = mapPointsIdx - arrayfun(@(x) nnz(x>outlierIdx), mapPointsIdx);
end
end
%% 
% |*helperEstimateTrajectoryError* calculate the tracking error.

function rmse = helperEstimateTrajectoryError(gTruth, cameraPoses)
locations       = vertcat(cameraPoses.AbsolutePose.Translation);
gLocations      = vertcat(gTruth.Translation);
scale           = median(vecnorm(gLocations, 2, 2))/ median(vecnorm(locations, 2, 2));
scaledLocations = locations * scale;

rmse = sqrt(mean( sum((scaledLocations - gLocations).^2, 2) ));
disp(['Absolute RMSE for key frame trajectory (m): ', num2str(rmse)]);
end
%% 
% |*helperUpdateGlobalMap*| update 3-D locations of map points after pose graph 
% optimization

function [mapPointSet, directionAndDepth] = helperUpdateGlobalMap(...
    mapPointSet, directionAndDepth, vSetKeyFrames, vSetKeyFramesOptim, poseScales)
%helperUpdateGlobalMap update map points after pose graph optimization
posesOld     = vSetKeyFrames.Views.AbsolutePose;
posesNew     = vSetKeyFramesOptim.Views.AbsolutePose;
positionsOld = mapPointSet.WorldPoints;
positionsNew = positionsOld;
indices     = 1:mapPointSet.Count;

% Update world location of each map point based on the new absolute pose of 
% the corresponding major view
for i = 1: mapPointSet.Count
    majorViewIds = directionAndDepth.MajorViewId(i);
    poseNew = posesNew(majorViewIds).T;
    poseNew(1:3, 1:3) = poseNew(1:3, 1:3) * poseScales(majorViewIds);
    tform = posesOld(majorViewIds).T \ poseNew;
    positionsNew(i, :) = positionsOld(i, :) * tform(1:3,1:3) + tform(4, 1:3);
end
mapPointSet = updateWorldPoints(mapPointSet, indices, positionsNew);
end
%% *Reference*
% [1] Mur-Artal, Raul, Jose Maria Martinez Montiel, and Juan D. Tardos. "ORB-SLAM: 
% a versatile and accurate monocular SLAM system." _IEEE Transactions on Robotics_ 
% 31, no. 5, pp 1147-116, 2015.
% 
% [2] Sturm, J??rgen, Nikolas Engelhard, Felix Endres, Wolfram Burgard, and Daniel 
% Cremers. "A benchmark for the evaluation of RGB-D SLAM systems". In _Proceedings 
% of IEEE/RSJ International Conference on Intelligent Robots and Systems_, pp. 
% 573-580, 2012.