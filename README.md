# DailyCredits

This hasn't been tested in full depth. Usage on your own risk.

## Commands
* sm_getcredits - Command to get the daily credits

## Config (configs/days.cfg)

```
"Days"
{
	"2"
	{
		"amount"  "30"
	}
	"1"
	{
		"amount"  "20"
	}
	"0"
	{
		"amount"  "10"
	}
}
```

You can add as much days as you want. **Important** The days are evaluated by their position in the config. Not by their name! (See the exampel)

## Database
You'll need to add a 'dailycredits' entry to you database.cfg. The tables will be created automaticly.
