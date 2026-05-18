

> [!WARNING]
> this readme is outdated. 
> look at [README.md](README.md) for the updated readme with the new backend provider (supabase instead of firebase).
> 
> this readme is really old and i didn't really update its style and formatting, so it might be a bit hard to read. but if you're interested in the old firebase backend and the reasons why I switched to supabase, you can read this readme.
> (this was around the time when I switched to supabase so I gave some examples here why supabase is better)


## auth and main backend service
for authentification ive descided to use **firebase auth**. firebase is a service by google that provides practically free authentification. it is pretty safe, performant and allows you to sign in / sign up using your email / phone number or other third party services like google, github or discord. for this project ive descided to only use email and google sign in since those are the two most common ones. <br>
you can also use firebase for connecting other services like googles **ad mob**, an ad provider for android and ios that automatically choses the best ads and partners for you to get the maximum income. it also supports personized ads, however ive descided not tu use that since the main audience of this app would be minors and the law is prety limiting there.<br>
micro transactions using third party providers like **stripe** are alo posible to connect to firebase.
### why connect everything?
its really handy to see all your incomes in one place

## database provider
as for the database provider, ive descided to use **supabase**. supabase is a backend provider containing its own services like auth and third party connections, however ive descided to use firebase for that because of the reasons ive stated above.<br>
the database uses **postgreSQL**. it provides a lot of features like rls policies, views, relatively high performance, functions and a lot more. 

### why not just use firestore?
firestore is a db provider in firebase. although it is a lot easier to connect to other firebase services, it has a lot of limitations. <br>
> skip to [pricing](#pricing) if your not interested in the code aspects

firestore uses **noSql**. noSql is a sql dialect like postgreSql, that stores its data a bit differently. ther are no tables you can access and connect, but instead there are collections, documents, subcollections and more. so if you want to access a users following for example, you would do something like this (pseudo code):

    users/{userId}/following/
the corresponding postgreSql statement would be something like this:

    SELECT following_id FROM following WHERE follower = {userId}

while that does seem easy at first, youre very limited when you try to do more advanced postgeSql queries in noSql. for example something like this wouldnt be possible to do in a single noSql request:

    SELECT * from profiles p, videos v where p.id = {userId} INNER JOIN v.author_id ON p.id

### pricing 
pretty much the main reason why i chose supabase is the pricing. <br>
when using supabase, you only pay for some of the servers resources. (in the pro plan, per month) you pay for
- database size: 8 gb are included, after that 0.125$ / gb
- monthly active users: 100,000 MAU, then 0.00325$ / MAU
- egress (data transfer): 250 gb included, after that 0.09$ / gb
- base pro plan cost: 25$
while this seems expensive, you have to compare this to the size of the data thats actually stored. since we dont store the actual image or video data but just the urls, the file size of one video is about 200 bytes at max. so you would be able to store about 40 million videos without exceeding the included database size. <br>
as for the egress fees, the users would need to watch over 41 million videos every day to exceed the included egress.
#### lets compare this to firestore.
firestore bills differently. there you pay per read / write. a read counts as a returned entry by a query, a write counts for every updated entry. this is problematic, since you need **a lot** of reads for an infinite scroller app. its not just the fact that the users scroll multiple times per minute and every scroll is one read, but the main problem is the recommendation algorithm, especially combined with the query limitations I sated above. so what does that mean? while you do have **some** possibilities of filtering the results before they count as a read, those are very limited. those limits include:

- the only filtering statements are complete basics like **equals, not equals, array in, in array**
- array in, in array are limited to only 10 elements

what that means is, that for example if you wanted to search videos containign a specific tag or want to do a text search you would actually need to pull every single element to the users device and filter it there. and every single returned element counts as one read. so if you had 100 million videos, every search would count as 100 million reads. <br>
while there are some third party services that allow text search, they are often relatively expensive and thats not the point. so what i want to say is that a good reccomendation algorithm is not really possible without high costs (trust me, ive done my research).<br>
additionally these reads are pretty expensive. Here is the pricing of reads, writes and deletes per 100k documents:
- reads: 0.03$
- writes: 0.09$
- deletes: 0.01$

## data storage provider
for storing the actual video data, profile images, thumbnails, subtitles and all of the actual heavy data i chose **Cloudflare**. cloudflare is especcially useful since it doesnt fee any egress costs, you only really pay for the actual storage. this is important since egress usually is pretty much the biggest bottleneck for social-media-like apps since the users are mass-downloading data from the server. if you take a look at tiktok for example single videos can reach immense amounts of views, reaching from the millions into the billions. since egress fees are free we only pay for the storage of a single video. there is however a limited amount of read operations. the operations are split into 2 categories, class A and class B operations. class A operations are more expensive but give you more power. besides of uploading videos we only need the class B operations which are a lot cheaper. here are the prices:
- class A operations: 1m free, then 4.50$/1m operations
- class B operations: 10m free, then 0.36$/1m operations

since profile images are being cached, we can count one sroll roughly as 1.2 class B operations.


