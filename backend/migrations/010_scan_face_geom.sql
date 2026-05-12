-- Where the face actually is on the photo. Lets the client overlay zones
-- on the real selfie instead of a generic oval.
-- Shape: {"bbox": [x0, y0, x1, y1]}  -- all values normalised to 0..1.
ALTER TABLE scans
    ADD COLUMN face_geom JSONB;
