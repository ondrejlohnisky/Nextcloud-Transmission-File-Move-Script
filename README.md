# Nextcloud Transmission File Move Script

<img width="379" alt="Snímek obrazovky 2023-08-10 v 5 43 47" src="https://github.com/ondrejlohnisky/Nextcloud-Transmission-File-Move-Script/assets/28301603/fff3f84c-2a35-4984-92e8-fcf709907c5f">

This Bash script automates the process of moving downloaded files from the Transmission download directory to a specified Nextcloud data directory. The script also interacts with the Transmission API to manage torrents based on their upload ratios.
====
## Requirements

- Bash shell environment
- `curl` command-line tool
- `jq` command-line JSON processor
- Nextcloud instance with administrative access

## Configuration

1. **Source and Destination Directories**: Set the `source_dir` and Nextcloud `nextcloud_data_dir` and `nextcloud_destination_dir` variables to the appropriate directories where downloaded files will be moved.

2. **Transmission Settings**: Replace `TRANSMISSION_URL`, `TRANSMISSION_USER`, and `TRANSMISSION_PASSWORD` with your actual Transmission settings.

3. **Upload Ratio Threshold**: Adjust the `upload_ratio_threshold` variable to set the upload ratio above which torrents should be moved.

## Usage

1. Make the script executable:

   ```bash
   chmod +x nextcloud_move_transmission_files.sh
   ```

2. Run the script:

   ```bash
   ./nextcloud_move_transmission_files.sh
   ```

3. The script will perform the following tasks:
   - Check torrent upload ratios and status using the Transmission API.
   - Move torrents with upload ratios above the threshold to the Nextcloud destination directory.
   - Change ownership of the moved files to `www-data:www-data`.
   - Stop and remove the torrent and its data using the Transmission API.

4. During script execution, press Ctrl+C or 'Q'/'q' to gracefully exit the loop.

5. After the script completes, it will output moved torrents and files ready for move. If torrents were moved, it will also trigger a Nextcloud file scan for the destination directory to update Nextcloud's file database.


Absolutely, here's a concise usage example with cron as root, in Markdown format for your README documentation:

## Automating with Cron Jobs (as Root)

You can automate the execution of the script using cron jobs. The following example demonstrates how to set up a cron job as the root user to run the script every 6 hours:

1. **Open the Root Crontab**:

   Run the following command to open the root user's crontab for editing:

   ```bash
   sudo crontab -e
   ```

2. **Add a Cron Job**:

   Add a line to the root crontab to schedule the script execution. To run the script every 6 hours, add the following line:

   ```bash
   0 */6 * * * /bin/bash /path/to/your/nextcloud_move_transmission_files.sh
   ```

   This line schedules the script to run at the 0th minute of every 6th hour.

   Replace `/path/to/your/nextcloud_move_transmission_files.sh` with the actual path to your script.

3. **Save and Exit**:

   Save your changes and exit the text editor.

Now, the script will be executed automatically by the cron job as the root user at the specified interval. Make sure your script is executable (`chmod +x`) and has the necessary permissions to execute.

Consider logging the output of your script to a file using `>>` to monitor any errors:

```bash
0 */6 * * * /bin/bash /path/to/your/nextcloud_move_transmission_files.sh >> /path/to/your/logfile.log 2>&1
```

Replace `/path/to/your/logfile.log` with the desired path for storing the script's output.

Remember to exercise caution when configuring cron jobs, especially as the root user, to ensure system stability and security.

## Important Notes

- Be cautious when using `sudo` within scripts, as it can pose security risks. Use elevated permissions only when necessary and implement proper security measures.
- Regularly review and test your script to ensure it functions as expected and to address any potential issues.
