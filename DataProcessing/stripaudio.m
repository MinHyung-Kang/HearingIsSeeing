di = dir('~/Downloads/UCF*/*/*');
for k = 1:size(di, 1)
    name = di(k).name;
    if ~di(k).isdir && strcmp(name(end-3:end), '.avi')
        
        [di(k).folder '/' di(k).name]

        aud = audioread([di(k).folder '/' di(k).name]);
        audiowrite([di(k).name '.wav'], aud, 44100);    
    end
    k

end