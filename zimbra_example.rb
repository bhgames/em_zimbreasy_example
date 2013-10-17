 
require 'em-zimbreasy'
require "active_support/all"
require "savon"
require "pry"

def no_prior_engagement_at?(times, start_time)
  return false unless times[:f]
  times[:f].each do |time_hash|
    if time_hash[:s] <= start_time and time_hash[:e] >= start_time + 30.minutes
      return true
    end
  end

  [:b, :t, :u, :n].each do |busy|
    if times[busy]
      times[busy].each do |time_hash|
        if time_hash[:s] <= start_time and time_hash[:e] >= start_time + 30.minutes
          return false
        end
      end
    end
  end
  return true
end

dir = File.dirname(File.expand_path(__FILE__))
@conf = YAML.load_file("#{dir}/zimbra.yaml")

start = Time.new(2013, 10, 11, 5, 0)
agent = @conf["agent"] # or your email account in zimbra
calendar_king = @conf["user"] 
@zs ||= Em::Zimbreasy::Account.new(@conf["user"], @conf["pass"], @conf["service_url"], :net_http);
@zm ||= Em::Zimbreasy::Mail.new(@zs);

failed_inv_ids = []
strange_inv_ids = [] 
begin
  100.times do |i|
  
    while(!no_prior_engagement_at?(@zm.get_free_busy(start-1.hours, start+1.hours, agent), start))
      puts "Hmm, looks like #{start.inspect} is not available. Moving up by 30 min."
      start = start + 30.minutes
    end
    puts "Creating appointment #{i} at #{start.inspect}."
  
    ics = @zm.create_appointment({
      :appointee_emails => [agent],
      :start_time => start,
      :end_time => (start + 30.minutes),
      :name => "Test APPT",
      :subject => "Test APPT",
      :desc => "Words are here.",
      :tz => "America/Chicago",
      :is_org => 1,
      :or => calendar_king
    })
  
    inv_id = Icalendar.parse(ics).first.events.first.uid
  
    puts "Created appt with id of #{inv_id} for #{i}. Checking to see if it made you busy then...(giving 5s to let zimbra reflect changes)"
  
    sleep(5)
    if !no_prior_engagement_at?(@zm.get_free_busy(start-1.hour, start+1.hour, agent), start)
      puts "As expected, #{inv_id}, the #{i}th appt, now causes free busy times to reflect their time slot as busy. Now modifying the appt to have no attendees, so it cancels."
    else
      puts "Strangely, creating this appt did not make you busy. Moving on."
      strange_inv_ids << inv_id
      next
    end
  
    @zm.modify_appointment({
       :inv_id => inv_id,
       :appointee_emails => [], # no emails means it will cancel the appt basically
       :start_time => start,
       :end_time => (start+30.minutes),
       :name => "FREE2",
       :subject => "FREE2",
       :desc => "FREE2",
       :tz => "America/Chicago",
       :is_org => 1,
       :or => calendar_king
    })

    puts "Now we expect #{inv_id} to not count against us in free-busy call. Performing free busy call after a 5 second sleep to give API time to reflect changes."
    
    sleep(5)
  
    if no_prior_engagement_at?(@zm.get_free_busy(start-1.hour, start+1.hour, agent), start)
      puts "The #{i}th appt #{inv_id} is now marked as free, because there is no more prior engagement at #{start}."
    else
      puts "Despite telling the appt #{inv_id} to be free(the #{i}th appt), it is still not being seen as free by free_busy times."
      failed_inv_ids << inv_id
    end

    puts "#{i} above------------------------------------------------------------"
  end

  puts "Failed inv ids are #{failed_inv_ids.inspect}"
  puts "Strange inv ids(inv ids that didn't make you busy even though you should have been) are #{strange_inv_ids.inspect}"
rescue Interrupt => e
  puts "Failed inv ids are #{failed_inv_ids.inspect}"
  puts "Strange inv ids(inv ids that didn't make you busy even though you should have been) are #{strange_inv_ids.inspect}"
end

