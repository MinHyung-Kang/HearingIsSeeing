cello = dir('/home/grangerlab/Downloads/UCF-101_FiveCategories/v_PlayingCello*.soundnet.h5');
% cello = dir('/home/grangerlab/Downloads/nottuned/v_PlayingCello*.soundnet.h5');

data = hdf5info(cello(1).name);
out1 = hdf5read(data.GroupHierarchy.Datasets(1));
for k = 2:size(cello, 1)
    name = cello(k).name;
    data = hdf5info(name);
    out1 = [out1; hdf5read(data.GroupHierarchy.Datasets(1))];
end

% daf = dir('/home/grangerlab/Downloads/UCF-101_FiveCategories/v_PlayingDaf*.soundnet.h5');
% data = hdf5info(daf(1).name);
% out2 = hdf5read(data.GroupHierarchy.Datasets(1));
% for k = 2:size(daf, 1)
%     name = daf(k).name;
%     data = hdf5info(name);
%     out2 = [out2; hdf5read(data.GroupHierarchy.Datasets(1))];
% end

% dhol = dir('/home/grangerlab/Downloads/nottuned/v_PlayingDhol*.soundnet.h5');
dhol = dir('/home/grangerlab/Downloads/UCF-101_FiveCategories/v_PlayingDhol*.soundnet.h5');
data = hdf5info(dhol(1).name);
out3 = hdf5read(data.GroupHierarchy.Datasets(1));
for k = 2:size(dhol, 1)
    name = dhol(k).name;
    data = hdf5info(name);
    out3 = [out3; hdf5read(data.GroupHierarchy.Datasets(1))];
end

% flute = dir('/home/grangerlab/Downloads/UCF-101_FiveCategories/v_PlayingFlute*.soundnet.h5');
% data = hdf5info(flute(1).name);
% out4 = hdf5read(data.GroupHierarchy.Datasets(1));
% for k = 2:size(flute, 1)
%     name = flute(k).name;
%     data = hdf5info(name);
%     out4 = [out4; hdf5read(data.GroupHierarchy.Datasets(1))];
% end

sitar = dir('/home/grangerlab/Downloads/UCF-101_FiveCategories/v_PlayingSitar*.soundnet.h5');
% sitar = dir('/home/grangerlab/Downloads/nottuned/v_PlayingSitar*.soundnet.h5');
data = hdf5info(sitar(1).name);
out5 = hdf5read(data.GroupHierarchy.Datasets(1));
for k = 2:size(sitar, 1)
    name = sitar(k).name;
    data = hdf5info(name);
    out5 = [out5; hdf5read(data.GroupHierarchy.Datasets(1))];
end

[coeff,score,latent,tsquared,explained,mu] = pca([out1; out3; out5]);
s = 1;
e = size(out1,1);
scatter3(score(s:e,1), score(s:e,2), score(s:e,3));
hold on;

% s = size(out1,1) + 1;
% e = size(out1,1) + size(out2,1);
% scatter3(score(s:e,1), score(s:e,2), score(s:e,3));

tmp = e;
e = e + size(out3,1);
s = tmp + 1;
scatter3(score(s:e,1), score(s:e,2), score(s:e,3));
% 
% tmp = e;
% e = e + size(out4,1);
% s = tmp + 1;
% scatter3(score(s:e,1), score(s:e,2), score(s:e,3));

tmp = e;
e = e + size(out5,1);
s = tmp + 1;
scatter3(score(s:e,1), score(s:e,2), score(s:e,3));
% scatter3(score(s:e,1), score(s:e,2), score(s:e,3));

