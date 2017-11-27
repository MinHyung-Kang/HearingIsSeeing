function extractframes(path)

	di = dir([path '*.avi'])
	for k = 1:size(di, 1)
        k
		if ~di(k).isdir

		    name = ['/home/grangerlab/Downloads/UCF-101_FiveCategories/' di(k).name '.wav.soundnet.h5'];
		    data = hdf5info(name);
		    audvecs = hdf5read(data.GroupHierarchy.Datasets(1));

		    ref = [path di(k).name];
		    x = VideoReader([path di(k).name]);

		    mov = vidplaycolor(ref);
		    movlen = get(x,'NumberOfFrames');
		    audlen = size(audvecs,1);
		    
		    for m = 1:audlen
		    	
                if m == 1
		    		im = 1;
                elseif m == audlen
		    		im = movlen;
                else
                    im = floor(movlen*m/audlen);
                end
                
		    	frame = read(x, im);
                frame = frame(41:230,61:260,:);
% 		    	frame = imresize(frame, [64 64]);
		    	imwrite(frame, [path di(k).name '.wav_' num2str(m) '.png']);

		    end

	    end

	end

end
