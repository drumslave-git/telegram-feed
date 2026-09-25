# fake_telegram

A `TelegramGateway` that answers from memory instead of TDLib.

- `ChannelsGateway`: channels and folders only; every other call answers empty. Read positions move as TDLib moves them.
- `TimelineGateway`: histories that page, search, live posts (`arrive`, `arrivedUnseen`), reactions and saved posts recorded for assertions.
- `FakeTelegram`: a whole account for the fake build and the UI tests: a scripted login (any phone number, code `12345`), three news channels in a folder, an archived channel, posts of every kind, sample media served from a directory, a discussion thread, and one post arriving every 30 seconds in the "Wire" channel.
- `fixturePost`, `fixtureHistory`, `fixtureChannel`: the fixture data the widget tests build on.
