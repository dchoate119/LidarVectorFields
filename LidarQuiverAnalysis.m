% Daniel Choate 
% Goal: Use quiver plot analyses for different data sets 
% Main code for paper 

% script for simulating lidar scans of input base stl scene (generated using
%autodesk inventor)
clear all 
close all

%import stl
% Locate file to display scene 
% Test evironment which Dan made
FileName = 'C:\Users\dchoa\OneDrive\Documents\TUFTS\Research\TestEnvironment.stl';  

% Open and read the stl file of point
OpenFile = stlread(FileName);

% Get vertices, faces, and normals from stl
vertices = OpenFile.Points;
faces = OpenFile.ConnectivityList;

% Generate extended object mesh
mesh = extendedObjectMesh(vertices,faces);

%rotate mesh to correct orientation
% mesh = rotate(mesh, [0, 0, 90]); %else
% mesh = rotate(mesh, [180, 0, 90]); %else
mesh = rotate(mesh, [270, 0, 90]); %for room

%init lidar unit
% Set mounting location to zero 
% SensorIndex distinguishes point clouds in a multi sensor system 
SensorIndex = 1;
sensor = monostaticLidarSensor(SensorIndex);
% LOCATION NOT DEFAULT ZERO 
sensor.MountingLocation = [0, 0, 0];

% Set parameters of virtual lidar unit to match velodyne VLP-16 ***
% Cycles per second 
sensor.UpdateRate = 10;
% Degree above and below sensor
sensor.ElevationLimits =  [-22, 10];  % was [-22, 2]; 22
sensor.RangeAccuracy = 0.02; %0.03; %0.01;
% Resolution around sensor 
sensor.AzimuthResolution = 0.05; %0.35;
% Degree between beams 
sensor.ElevationResolution = 0.4; %0.4;
% sensor.MaxRange = 50;
sensor.HasNoise = false;

% Create a tracking scenario. Add an ego platform and a target platform.
scenario = trackingScenario;

% LOCATION OF SENSOR, sets a platform for the scenario 
ego = platform(scenario, 'Position', [0, 0, 0]);

% Modifies position of the scene, position raised 3 m in this case 
% Velocity (20 m/s in this case)
% SECOND SCAN IS TAKEN 1 ROTATION LATER
target = platform(scenario,'Trajectory',kinematicTrajectory('Position',[0 0 3],'Velocity',[10 10 0], 'AngularVelocity', [0., 0., 0.5])); %with rotatation 

target.Mesh = mesh;

%specify bounding box for test env ~~~~~~~~~~~~~~
% Specific for the test scene which Dan created 
target.Dimensions.Length = 25; %32
target.Dimensions.Width = 25; %32
target.Dimensions.Height = 11; %16; %12 

% Obtain the mesh of the target viewed from the ego platform after advancing the scenario one step forward.
% Assuming scenario has an automatic 0.1 second value
advance(scenario);
tgtmeshes = targetMeshes(ego);
% Use the created sensor to generate point clouds from the obtained target mesh.
time = scenario.SimulationTime;
[ptCloud1, config, clusters] = sensor(tgtmeshes, time);
blue_cloud = target.Position;
blue_angle = target.Orientation;

%repeat for 2nd scan
advance(scenario);
tgtmeshes = targetMeshes(ego);
time = scenario.SimulationTime;
[ptCloud2, config, clusters] = sensor(tgtmeshes, time);
orange_cloud = target.Position;
orange_angle = target.Orientation;

% NDT_Error = zeros(simulations,3);

relpos = orange_cloud - blue_cloud;
relangle = orange_angle; % Known that inital angle is zero
X_Y_Yaw = [relpos(1), relpos(2), deg2rad(relangle(1))];


% Remove ground plane points 
% groundIndx1 = find(ptCloud1(:,3) < 0);
% % aboveIndx1 = find(ptCloud1(:,3) > 2);
% ptCloud1(groundIndx1, :) = [];
% % ptCloud1(aboveIndx1, :) = [];
% groundIndx2 = find(ptCloud2(:,3) < 0);
% % aboveIndx2 = find(ptCloud2(:,3) > 2);
% ptCloud2(groundIndx2, :) = [];
% % ptCloud2(aboveIndx2, :) = [];

movingCloud = pointCloud(ptCloud2); 
staticCloud = pointCloud(ptCloud1); 

% First NDT scan matching test 
% BEFORE SHADOW MITIGATION ALGORITHM
% Set voxel size for NDT alignment
gridstep = 3; %voxel size
%**** Add an initial guess 
alpha = deg2rad(relangle(1));
rotationM = [cos(alpha) -sin(alpha) 0; sin(alpha) cos(alpha) 0; 0 0 1];
% Guess must be in the form of a rotation matrix and a 1x3 translation 
tformguess = rigid3d((rotationM)^-1, -relpos);
% rigidtform3d = 0
tform_ndt = pcregisterndt(movingCloud, staticCloud, gridstep, "InitialTransform", tformguess,"MaxIterations", 10000); 

% Calculate error of the first NDT scan match 
% WITHOUT SHADOW MITIGATION
tform_ndt_tran = tform_ndt.Translation;
NDT_Results = [tform_ndt.Translation(1) tform_ndt.Translation(2) -acos(tform_ndt.R(1,1))];
NDT_Error = X_Y_Yaw + NDT_Results

% All shadowing and voxel distribution done after alignment
ptCloud2b = ptCloud2;
ptCloud2 = (ptCloud2 + tform_ndt.Translation) * ((tform_ndt.R)^-1);
% Plot ptCloud1 and translated ptCloud2 using plot3 function
plot3(ptCloud1(:,1),ptCloud1(:,2),ptCloud1(:,3),'.')
hold on
% plot3(ptCloud2b(:,1),ptCloud2b(:,2),ptCloud2b(:,3),'.')
% hold on 
plot3(ptCloud2(:,1),ptCloud2(:,2),ptCloud2(:,3),'.')
% legend("Original", "Matched Scene")

% *********** POLAR COORDS *********************
% Convert cartesian coordiates to polar coordinates
% After translation, before NDT scan matching algorithm
initial_o = [0 0 0];

ptCloud1_pol = conv_to_polar(ptCloud1, initial_o);
ptCloud2_pol = conv_to_polar(ptCloud2, initial_o);


%******** VOXEL DISTRIBUTION **************

% CARTESIAN ********
% Dividing voxels in a cartesian grid
L = target.Dimensions.Length;
W = target.Dimensions.Width;
H = target.Dimensions.Height;


% Determine side length of the voxel
v_side = 1;
volume = L*W*H;
v_number = volume/v_side;

% Add 2 additional voxels to support error of NDT (1 should suffice)
% Potentially just add 1 meter?
L_2 = target.Dimensions.Length + 2*v_side; % + 1
W_2 = target.Dimensions.Width + 2*v_side; % + 1
H_2 = target.Dimensions.Height + 2*v_side; % + 1
v_L = ceil(L_2/v_side);
v_W = ceil(W_2/v_side);
v_H = ceil(H_2/v_side);

% Voxels1_cart = cart_voxel_dist(ptCloud1, v_side, L, W, H);
% Voxels2_cart = cart_voxel_dist(ptCloud2, v_side, L, W, H);


% SPHERICAL ********
% Dividing voxels in a spherical grid as opposed to cartesian 
% Set parameters of the voxel distribution
top_elev = sensor.ElevationLimits(1, 2) + 5;
bot_elev = sensor.ElevationLimits(1, 1) - 5;
elev_dif = top_elev - bot_elev;

% Degrees of arclength of voxel  
arc_d = 10; %3.6 %36 
% Amount of voxels divided around circumference
v_az = ceil(360/arc_d);
% Degrees per band elevation
dpb = 2;
% Determine amount of bands per azimuth voxel
band_des = 2;
band_amt = band_des*dpb;
% Determine amount of voxels through elevation
% NOTE: for VLP-16, 1 band every 2 degrees 
v_elev = ceil(elev_dif/band_amt);

% Define amount below horizontal which elevation reaches
zero_el = 0 - sensor.ElevationLimits(1, 1);

Voxels1 = sph_vox_dist(ptCloud1_pol, arc_d, band_amt, elev_dif, zero_el);
Voxels2 = sph_vox_dist(ptCloud2_pol, arc_d, band_amt, elev_dif, zero_el);


% *************** Mean calculations ************************
% % *** CARTESIAN 
% means1_cart = calc_means_cart(Voxels1_cart, ptCloud1, v_L, v_W, v_H);
% means2_cart = calc_means_cart(Voxels2_cart, ptCloud2, v_L, v_W, v_H);

% *** SPHERICAL
% Use either the ORIGINAL OR NEW POINT CLOUDS
means1 = calc_means_sph(Voxels1, ptCloud1, v_az, v_elev);
means2 = calc_means_sph(Voxels2, ptCloud2, v_az, v_elev);

% means_dif_cart = calc_mean_dif_cart(means1_cart, means2_cart, Voxels1_cart, Voxels2_cart, v_L, v_W, v_H);
means_dif = calc_mean_dif_sph(means1, means2, Voxels1, Voxels2, v_az, v_elev);

% *************** Quiver Plot ******************************
% Define total number of voxels 
% Change which means array based on desired starting location 
% Define positions for desired location 
pos_x = 1; 
pos_y = 2;
pos_z = 3;

% % CARTESIAN ****
% vox_number_cart = v_L*v_W*v_H;
% X_q_cart = quiver_setup_cart(vox_number_cart, means1_cart, v_L, v_W, v_H, pos_x);
% Y_q_cart = quiver_setup_cart(vox_number_cart, means1_cart, v_L, v_W, v_H, pos_y);
% Z_q_cart = quiver_setup_cart(vox_number_cart, means1_cart, v_L, v_W, v_H, pos_z);
% U_q_cart = quiver_setup_cart(vox_number_cart, means_dif_cart, v_L, v_W, v_H, pos_x);
% V_q_cart = quiver_setup_cart(vox_number_cart, means_dif_cart, v_L, v_W, v_H, pos_y);
% W_q_cart = quiver_setup_cart(vox_number_cart, means_dif_cart, v_L, v_W, v_H, pos_z);

% SPHERICAL ****
% Set total number of voxels
vox_number = v_az*v_elev;
X_q = quiver_setup_sph(vox_number, means1, v_az, v_elev, pos_x);
Y_q = quiver_setup_sph(vox_number, means1, v_az, v_elev, pos_y);
Z_q = quiver_setup_sph(vox_number, means1, v_az, v_elev, pos_z);
U_q = quiver_setup_sph(vox_number, means_dif, v_az, v_elev, pos_x);
V_q = quiver_setup_sph(vox_number, means_dif, v_az, v_elev, pos_y);
W_q = quiver_setup_sph(vox_number, means_dif, v_az, v_elev, pos_z);

% Form quiver plot 
% figure(2)
% quiver3(X_q_cart, Y_q_cart, Z_q_cart, U_q_cart, V_q_cart, W_q_cart)

% CHANGE TO FIGURE 3 IF ALSO USING CARTESIAN 
figure(2)
quiver3(X_q, Y_q, Z_q, U_q*2, V_q*2, W_q*2, 'AutoScale', 'off')
% axis equal


%**********************************************************
% ********************** Functions ************************
% *********************************************************

% Function that converts the point cloud to polar coordinates 
% Inputs: Point Cloud in cartesian coords, Origin
% Outputs: Polar Point Cloud 
function ptCloud_polar = conv_to_polar(ptCloud, origin)
    ptCloud_polar = zeros(length(ptCloud),3);
    for i = 1:length(ptCloud)
        X = ptCloud(i,1) - origin(1);
        Y = ptCloud(i,2) - origin(2);
        Z = ptCloud(i,3) - origin(3);
        [theta, rho, z] = cart2pol(X,Y,Z);
        ptCloud_polar(i,:) = [theta, rho, z];
        azi_correct = atan2(Y,X);
        ptCloud_polar(i,1) = azi_correct;
        rho_correct = sqrt(X^2 + Y^2 + Z^2);
        ptCloud_polar(i,2) = rho_correct;
        elevation = atan(Z/sqrt(X^2 + Y^2));
        ptCloud_polar(i,3) = elevation;
    end
end

% Function that places cartesian coordinates into cartesian voxels 
% Inputs:
% 1) Cartesian point cloud 
% 2) Voxel side length
% 3) Length of scene 
% 4) Width of scene
% 5) Height of scene
% Outputs: voxel distribution 
function Voxels = cart_voxel_dist(ptCloud, v_side, L, W, H)
    L_2 = L + 2*v_side;
    W_2 = W + 2*v_side;
    H_2 = H + 2*v_side;

    Voxels{ceil(L_2/v_side),ceil(W_2/v_side),ceil(H_2/v_side)} = [];

    for q = 1:length(ptCloud)
        x = ptCloud(q,1);
        y = ptCloud(q,2);
        z = ptCloud(q,3);
        xVoxelInd = ceil((x + L/2)/v_side);
        yVoxelInd = ceil((y + W/2)/v_side);
        zVoxelInd = ceil((z + H/2)/v_side);
        % Added ERROR CHECK for zero value
        if xVoxelInd < 1; xVoxelInd = 1; end
        if yVoxelInd < 1; yVoxelInd = 1; end
        if zVoxelInd < 1; zVoxelInd = 1; end
        % Check if number is NAN
        if isnan(x) | isnan(y) | isnan(z)
        else
            % Add row number from point cloud to cell array for given vox
            Voxels{xVoxelInd, yVoxelInd, zVoxelInd} = [Voxels{xVoxelInd, yVoxelInd, zVoxelInd} q];
        end
    end
end


% Function that places polar coordinates into spherical voxels
% Inputs:
% 1) Polar point cloud
% 2) Arc length per voxel (az)
% 3) Band amount (elev)
% 4) Difference in elevation
% 5) Zero elevation point  
% Outputs: Voxel distribution
function Voxels = sph_vox_dist(ptCloud, arc_d, band_amt, elev_dif, zero_el)
    v_az = ceil(360/arc_d);
    v_elev = ceil(elev_dif/band_amt);
    Voxels{v_az, v_elev} = [];

    for q = 1:length(ptCloud)
        azi = rad2deg(ptCloud(q,1));
        rho = ptCloud(q,2);
        elev = rad2deg(ptCloud(q,3));

        % Create an indice for the azimuth and elevation 
        % NOTE: Theta (azimuth) goes from -pi to pi
        % NOTE: Elevation (elev) goes from specified range
        azVoxelInd = ceil((azi+180)/arc_d);
        elevVoxelInd = ceil((elev + zero_el)/band_amt);
        % if elevVoxelInd>8; keyboard; end
        % Add an error check for zero value 
        if azVoxelInd < 1; azVoxelInd = 1; end
        if elevVoxelInd < 1; elevVoxelInd = 1; end
        % Check if number is a NAN
        if isnan(azi) | isnan(rho) | isnan(elev)
        else
            Voxels{azVoxelInd, elevVoxelInd} = [Voxels{azVoxelInd, elevVoxelInd} q];
        end
    end
end

% Function that implements shadow mitigation algorithm
% Inputs: 
% 1) Polar point cloud
% 2) Array of voxels with distributed pts
% 3) Jump param
% 4) Min pts param
% 5) Arc length per voxel (az)
% 6) Band amount (elev)
% 7) Difference in elevation
% 8) Zero elevation point 
% Outputs: Array of points to be effected by shadow mitigation 
function points_disc = shadow_mitig(ptCloud_pol, Voxels, jump, min_pts, arc_d, band_amt, elev_dif, zero_el)
    points_disc = [];
    V_rad = zeros(length(ptCloud_pol), 1);
    v_az = ceil(360/arc_d);
    v_elev = ceil(elev_dif/band_amt);
    for i = 1:v_az
        for j = 1:v_elev
            az_upper = (i*arc_d)-180;
            az_lower = (i*arc_d)-180 - arc_d;
            elev_upper = (j*band_amt)-zero_el;
            elev_lower = (j*band_amt)-zero_el-band_amt;
            Voxelij = Voxels{i,j};
            radii = ptCloud_pol(Voxelij,2);
            Vij = sort(radii);
            l_min = 1;
            l_max = length(Vij);
            for l = 2:length(Vij)
                diff = Vij(l) - Vij(l-1);
                if diff > jump
                    if l - l_min > min_pts
                        l_max = l-1;
                    else
                        l_min = l;

                    end
                end
            end
            % Add a check for empty voxels
            if length(Vij) == 0
            else
                r_min = Vij(l_min);
                r_max = Vij(l_max);
                below_rr = find(ptCloud_pol(:,2)<r_min & az_lower<rad2deg(ptCloud_pol(:,1)) & rad2deg(ptCloud_pol(:,1))<az_upper & elev_lower<rad2deg(ptCloud_pol(:,3)) & rad2deg(ptCloud_pol(:,3))<elev_upper);
                % ptCloud_new(below_rr,:) = NaN;
                above_rr = find(ptCloud_pol(:,2)>r_max & az_lower<rad2deg(ptCloud_pol(:,1)) & rad2deg(ptCloud_pol(:,1))<az_upper & elev_lower<rad2deg(ptCloud_pol(:,3)) & rad2deg(ptCloud_pol(:,3))<elev_upper);
                % ptCloud_new(above_rr,:) = NaN;
                points_vox_disc = cat(1, below_rr, above_rr);
                points_disc = cat(1, points_vox_disc, points_disc);
            end
        end
    end
end

% Function that finds the mean point distribution in each CARTESIAN voxel
% Inputs:
% 1) Voxels - distributed
% 2) Original point cloud of the voxels 
% 3) Voxels in the Length 
% 4) Voxels in the width 
% 5) Voxels in the height
% Outputs: Voxels with mean point in each voxel 
function voxels_m = calc_means_cart(Voxels, ptCloud, v_L, v_W, v_H)
    voxels_m{v_L, v_W, v_H} = [];
    for i = 1:v_L
        for j = 1:v_W
            for k = 1:v_H
                x_m = ptCloud(Voxels{i,j,k},1);
                y_m = ptCloud(Voxels{i,j,k},2);
                z_m = ptCloud(Voxels{i,j,k},3);
                % Check if number is a NAN
                if isnan(x_m) | isnan(y_m) | isnan(z_m)
                else
                    mean_pt = [mean(x_m), mean(y_m), mean(z_m)];
                    voxels_m{i,j,k} = mean_pt;
                end
            end
        end
    end
end


% Function that finds the mean point distribution in each SPHERICAL voxel
% Inputs: 
% 1) Voxels - distributed
% 2) Original point cloud of the voxels
% 3) Voxels in the azimuth 
% 4) Voxels in the elevation range
% Outputs: Voxels with mean point in each voxel
function voxels_m = calc_means_sph(Voxels, ptCloud, v_az, v_elev)
    voxels_m{v_az,v_elev} = [];
    for i = 1:v_az
        for j = 1:v_elev
            x_m = ptCloud(Voxels{i,j},1);
            y_m = ptCloud(Voxels{i,j},2);
            z_m = ptCloud(Voxels{i,j},3);
            % Check if number is a NAN
            if isnan(x_m) | isnan(y_m) | isnan(z_m)
            else
                mean_pt = [mean(x_m), mean(y_m), mean(z_m)];
                voxels_m{i,j} = mean_pt;
            end
        end
    end
end

% Function that finds difference of means for CARTESIAN point clouds
% Inputs:
% 1) Means of voxels 1
% 2) Means of voxels 2
% 3) Voxel distribution 1
% 4) Voxel distribution 2
% 5) Voxels in the length
% 6) Voxels in the width
% 7) Voxels in the height
% Outputs: Voxels with mean difference between each voxel 
function means_dif = calc_mean_dif_cart(means1, means2, voxels1, voxels2, v_L, v_W, v_H)
    means_dif{v_L, v_W, v_H} = [];
    for i = 1:v_L
        for j = 1:v_W
            for k = 1:v_H
                % Specify a minimum number of points to recognize a voxel 
                if length(voxels1{i,j,k}) >= 100 && length(voxels2{i,j,k}) >= 100
                    x_dif = means2{i,j,k}(1,1) - means1{i,j,k}(1,1);
                    y_dif = means2{i,j,k}(1,2) - means1{i,j,k}(1,2);
                    z_dif = means2{i,j,k}(1,3) - means1{i,j,k}(1,3);
                    mean_dif_pt = [x_dif, y_dif, z_dif];
                    means_dif{i,j,k} = mean_dif_pt;
                else
                    means_dif{i,j,k} = [0 0 0];
                end
            end
        end
    end
end

% Function that finds difference of means for SPHERICAL point clouds 
% Inputs:
% 1) Means of voxels 1
% 2) Means of voxels 2
% 3) Voxel distribution 1
% 4) Voxel distribution 2
% 5) Voxels in the azimuth
% 6) Voxels in the elevation range
% Outputs: Voxels with mean difference bewteen each voxel 


function means_dif = calc_mean_dif_sph(means1, means2, voxels1, voxels2, v_az, v_elev)
    means_dif{v_az, v_elev} = [];
    for i = 1:v_az
        for j = 1:v_elev
            % Specify a minimum number of points to recognize a voxel 
            if length(voxels1{i,j}) >= 100 && length(voxels2{i,j}) >= 100
                x_dif = means2{i,j}(1,1) - means1{i,j}(1,1);
                y_dif = means2{i,j}(1,2) - means1{i,j}(1,2);
                z_dif = means2{i,j}(1,3) - means1{i,j}(1,3);
                mean_dif_pt = [x_dif y_dif z_dif];
                means_dif{i,j} = mean_dif_pt;
            else
                means_dif{i,j} = [0 0 0];
            end
        end
    end
end

% Function that manufactures a quiver plot setup for CARTESIAN COORDS
% Inputs:
% 1) Number of total voxels 
% 2) Mean distribution within each voxel
% 3) Voxels in length
% 4) Voxels in width 
% 5) Voxels in height
% 6) X,Y,Z position desired
function quiv_i = quiver_setup_cart(vox_number, means, v_L, v_W, v_H, pos)
    quiv_i = zeros(vox_number, 1);
    num = 1;
    for i = 1:v_L
        for j = 1:v_W
            for k = 1:v_H
                position_ii = means{i,j,k}(1,pos);
                quiv_i(num) = position_ii;
                num = num + 1;
            end
        end
    end
end

% Function that manufactures a quiver plot setup for SPHERICAL COORDS
% Inputs: 
% 1) Number of total voxels 
% 2) Mean distribtuion within each voxel 
% 3) Voxels in the azimuth
% 4) Voxels in the elevation range
% 5) X,Y,Z position desired

function quiv_i = quiver_setup_sph(vox_number, means, v_az, v_elev, pos)
    quiv_i = zeros(vox_number, 1);
    num = 1;
    for i = 1:v_az
        for j = 1:v_elev
            position_ii = means{i,j}(1,pos);
            quiv_i(num) = position_ii;
            num = num + 1;
        end
    end
end

