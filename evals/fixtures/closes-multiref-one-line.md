## Summary

Add user profile feature with avatar upload support.

## Changes

- `plugins/profile/handler.py` — add avatar upload endpoint
- `plugins/profile/schema.py` — add avatar URL field to user model

## Test plan

- [ ] Upload a valid JPEG and confirm it appears in the profile view.
- [ ] Upload an oversized file and confirm the 413 error is returned.

Closes #88 #89 #90
