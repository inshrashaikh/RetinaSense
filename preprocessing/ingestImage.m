function c = ingestImage(meta, imagePath)
%INGESTIMAGE  Stage 0: validate and downscale a fundus image into a Case.
%
%   c = ingestImage(meta, imagePath)
%
%   meta:      struct with patientId, eye, timestamp, phcId
%   imagePath: path to a JPG/PNG fundus image, OR '' to generate a synthetic
%              mock image (Sprint 0: no datasets required).
%
%   Returns a Case whose 'image' is the downscaled working RGB (uint8, max edge
%   <= config.preprocess.maxWorkingSize, aspect preserved) and 'meta' is set.
%   Downscale is here so later stages (IQA, CNN) see a bounded input size.
%
%   CONTRACT (docs/ARCHITECTURE.md §5 Stage 0):
%     in  : file path + patient meta
%     out : c.image HxWx3 uint8, c.meta
%     errs: RetinaSense:ingestImage:FileNotFound
%           RetinaSense:ingestImage:DecodeFailed
%     cfg : config/preprocess_config.m (maxWorkingSize, inputFormats)
%
%   TODO(Sprint 2+): real decode via imread + imresize; this mock supports the
%   synthetic image path so the pipeline runs without datasets.

    p = preprocess_config();

    c = newCase();
    c.meta = meta;

    % --- Resolve input: file or synthetic mock ---
    if isempty(imagePath)
        c.image = makeSyntheticImage(p.maxWorkingSize);
        c.imagePath = '';  % synthetic; not backed by a file
    else
        if ~exist(imagePath, 'file')
            raiseError('ingestImage', 'FileNotFound', ...
                'Image not found: %s', imagePath);
        end
        [~, ~, ext] = fileparts(imagePath);
        if ~any(strcmpi(ext, p.inputFormats))
            raiseError('ingestImage', 'UnsupportedFormat', ...
                'Unsupported image format ''%s''. Allowed: %s.', ext, ...
                strjoin(p.inputFormats, ', '));
        end
        try
            % Read the file as an image (JPG/PNG).
            c.image = imread(imagePath);
            c.imagePath = imagePath;
        catch
            raiseError('ingestImage', 'DecodeFailed', ...
                'Could not decode image: %s', imagePath);
        end
    end

    % --- Validate + downscale (aspect preserved) ---
    if isempty(c.image) || ndims(c.image) ~= 3 || size(c.image,3) ~= 3
        raiseError('ingestImage', 'InvalidImage', ...
            'Expected an RGB image, got %s.', helperSizeStr(c.image));
    end

    c.image = downscaleToMax(c.image, p.maxWorkingSize);
    c.image = im2uint8(c.image);
end

function img = makeSyntheticImage(maxEdge)
%MAKE_SYNTHETICIMAGE  Deterministic pseudo-retina RGB image (mock only).
    rng(1, 'twister');
    big = 512;
    if maxEdge < big; big = maxEdge; end
    % Disc-like bright blob center, vignette-less, mild texture.
    [yy, xx] = ndgrid(1:big);
    rr = sqrt((xx-big/2).^2 + (yy-big/2).^2);
    disc = double(rr <= big*0.22);
    % Slightly darker fundus everywhere to give contrast.
    bg = 70 + 40*rand(big);
    r = uint8(bg + 120*disc);
    g = uint8(bg + 60*disc);
    b = uint8(bg + 20*disc);
    img = cat(3, r, g, b);
end

function im = downscaleToMax(im, maxEdge)
    [h, w, ~] = size(im);
    m = max(h, w);
    if m > maxEdge
        s = maxEdge / m;
        im = imresize(im, s);
    end
end

function s = helperSizeStr(im)
    if isempty(im)
        s = '[]';
    else
        sz = size(im);
        s = sprintf('%d', sz(1));
        for k = 2:numel(sz)
            s = sprintf('%sx%d', s, sz(k));
        end
    end
end
