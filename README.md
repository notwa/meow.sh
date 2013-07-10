# meow.sh

Scrapes the title, torrent link, and timestamp
for every new release matching user-defined regular expressions.
Optionally sends them to a local instance of transmission-remote.

## Usage

Define regexes in `config.sh` and
execute `../path/to/meow.sh/run`.
You may wish to redirect or silence
stdout when running as a cron job.

## License

These scripts are hardly unique so
I'm not signing my name on them and
I'm not applying any license.
Just pretend they're under the [WTFPL][0]
if you really want to.

[0]: http://www.wtfpl.net/txt/copying/
