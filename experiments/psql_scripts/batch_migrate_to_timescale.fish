set first_ts 24309440
set start $first_ts
set last_ts 29646719
set step (math "60 * 24 * 7")

set n_chunks (math "($last_ts - $first_ts + 1) / $step")
set i_chunk 0

# timing stuff
set start_time (date +%s)
set avg_time 0

echo "We are starting!"
while test $start -le $last_ts

  set end (math $start + $step)
  set step_start_time (date +%s)

  sudo -u postgres psql -d stockdb -c "
    INSERT INTO hist_minutely_bars
    SELECT *
    FROM hist_minutely_bars_old
    WHERE ts >= $start
      AND ts < $end
    ON CONFLICT (symbol, ts) DO NOTHING;
  "

  if test $status -ne 0
      echo "Batch failed at [$start, $end), chunk $i_chunk. Stopping."
      break
  end

  set chunk_time (math (date +%s) - $step_start_time )
  set avg_time (math "
    ($avg_time * $i_chunk + $chunk_time)/
    ($i_chunk + 1)
  ")
  set time_to_fin (math "($n_chunks - $i_chunk - 1) * $avg_time")
  set time_of_fin (date -d @(math (date +%s) + $time_to_fin))

  echo "Loaded ts in [$start, $end). Progress: "(math "100 * ($i_chunk + 1) / $n_chunks")"%. Finish time approx $time_of_fin."
  echo "Chunk took $chunk_time sec"

  set i_chunk (math $i_chunk + 1)
  set start $end

end
