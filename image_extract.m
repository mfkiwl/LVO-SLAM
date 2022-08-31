% for frame = 1 : size(msgStructs,1)
frame = 1
		% Extract the frame from the movie structure.
        img = readImage(msgStructs{frame});
        thisFrame = readImage(msgStructs{frame,1});
% 		thisFrame = msgStructs{1};
		outputBaseFileName = sprintf('Frame_%4.4d.png', frame);
		outputFullFileName = fullfile("/path_to_directory/Datasets/rosbag_xxx_images", outputBaseFileName);
		imwrite(thisFrame, outputFullFileName, 'png');
% end
