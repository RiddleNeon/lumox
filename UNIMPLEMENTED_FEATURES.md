## Unimplemented Features

I Wasn't able to implement the following features due to time constraints, technical difficulties, or because they were out of scope for the project:

- [ ] Video Uploading
- [ ] Advanced Recommendation Algorithm
- [ ] Video Transcribing
- [ ] Video Thumbnail Generation

---

## Video Uploading

I wasn't able to implement video uploading to cloudflare, because if you want to use cloudflare you need to enter your credit card details, and I didn't want to do that.

For profile images and thumbnails I used Cloudinary, which has a free tier that allows you to upload images without entering your credit card details. However, for video uploading, I would have needed to use Cloudflare R2, because Cloudinary has not a lot of free storage.

---

## Advanced Recommendation Algorithm

I wasn't able to implement an advanced recommendation algorithm, because it would have required a lot of time and resources to implement.

I technically have all the code to do it already, since I implemented a working tag-based recommendation algorithm for the firebase backend, but since I switched to supabase, I didn't have time to implement it again for the new backend.

---

## Video Transcribing

For usable video transcribing I would have needed to use a third-party service like OpenAI's Whisper API, which is not free and would have required a lot of time to implement.

I implemented a basic video transcribing feature that uses local whisper, but that would require the user to wait a long time, since it would need to download the ~2GB model and then transcribe the video, which is not a good user experience.

In my testing the transcription process took around 5 minutes for a 1-minute video, which is not acceptable for a production application.

---

## Video Thumbnail Generation

Video Thumbnail Generation requires processing the video to extract a frame and then upload it as an image.

Cloudinary provides a way to generate thumbnails from videos, but there are heavy rate limits on the free tier.

And as stated above, I wasn't able to use Cloudflare R2 for video uploading, so I couldn't use their thumbnail generation feature either.