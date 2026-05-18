## backend
as for the database, auth and analytics provider, ive descided to use **supabase**. supabase is a backend provider containing its own services like auth and third party connections.<br>
the database uses **postgreSQL**. it provides a lot of features like rls policies, views, relatively high performance, functions and a lot more. **supabase auth** is an included auth service provided by supabase. it contains basic e-mail authentification and sms verification. It also lets you link third-party services as auth providers. this includes google, github, discord, twitter (x), facebook, spotify and a lot more. however ive chosen to only use e-mail verification for now since i dont want to overcomplicate that since it is at the end of the day just a school project and every third party service requires you to register your app, verify, send an application and so on.

### pricing
pretty much the main reason why i chose supabase is the pricing. <br>
when using supabase, you only pay for some of the servers resources. (in the pro plan, per month) you pay for
- database size: 8 gb are included, after that 0.125$ / gb
- monthly active users: 100,000 MAU, then 0.00325$ / MAU
- egress (data transfer): 250 gb included, after that 0.09$ / gb
- base pro plan cost: 25$

while this seems expensive, you have to compare this to the size of the data thats actually stored. since we dont store the actual image or video data but just the urls, the file size of one video is about 200 bytes at max. so you would be able to store about 40 million videos without exceeding the included database size. <br>
as for the egress fees, the users would need to watch over 41 million videos every day to exceed the included egress.

## data storage provider
for storing the actual video data, profile images, thumbnails, subtitles and all of the actual heavy data i chose **Cloudflare**. cloudflare is especcially useful since it doesnt fee any egress costs, you only really pay for the actual storage and the operations. this is important since egress usually is pretty much the biggest bottleneck for social-media-like apps since the users are mass-downloading data from the server. if you take a look at tiktok for example single videos can reach immense amounts of views, reaching from the millions into the billions. since egress fees are free we only pay for the storage of a single video. there is however a limited amount of included free read operations. the operations are split into 2 categories, class A and class B operations. class A operations are more expensive but give you more power. besides of uploading videos we only need the class B operations which are a lot cheaper. here are the prices:
- class A operations: 1m free, then 4.50$/1m operations
- class B operations: 10m free, then 0.36$/1m operations

since profile images are being cached, we can count one sroll roughly as 1.2 class B operations.