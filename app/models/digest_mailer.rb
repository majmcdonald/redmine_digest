require "mailer"
#require "actionmailer"

class DigestMailer < Mailer
	#public :self.test
	def self.test(user)
		options = {}
		project = Project.find :first
		options[:project] = project[:name]
		options[:test_email] = user.mail
		log "Sending test email to %s." % user.mail

		return DigestMailer.digests(options)
	end

	def digest(project, recip_emails, body, days)
		#set_language_if_valid user.language
		recipients recip_emails
		#recipients Setting.mail_from
		#cc(['email@somewhere.com'])
		if l(:this_is_gloc_lib) == 'this_is_gloc_lib'
			subject l(:mail_subject_digest, issues.size, days)
		else
			subject l(:mail_subject_digest, :project => project, :count => body[:events].size, :days => days )
		end
		content_type "multipart/alternative"

		#part :content_type => "text/plain", :body => render_message("digest.text.plain.rhtml", body)
		#part :content_type => "text/html", :body => render_message("digest.text.html.rhtml", body)
		render_multipart('digest', body)
		puts 'Email sent.'
		RAILS_DEFAULT_LOGGER.debug 'Email sent.'
	end

	def self.fill_events(project, body={})
		#days = Setting.activity_days_default.to_i
		# From midnight of "from" (1st tick of the day)
		# To midnight of "to" + 1 (1st tick of the next day)
		# TODO: Do we need some error checking?
		start = body[:start]
		days = body[:days]
		params = {:from => Time.now}
		date_from = params[:from].to_date - start
		date_to = date_from + days
		body[:start] = start
		body[:date_to] = date_to
		body[:date_from] = date_from
		puts "Summarizing: %s to %s (%d days)" % [ date_from.to_s, date_to.to_s, days]
		puts l(:label_date_from_to, :start => format_date(date_to - days), :end => format_date(date_to-1))

		with_subprojects = params[:with_subprojects].nil? ? Setting.display_subprojects_issues? : (params[:with_subprojects] == '1')
		params["show_issues"] = 1
		params["show_changesets"] = 1
		params["show_news"] = 1
		params["show_documents"] = 1
		params["show_files"] = 1
		params["show_wiki_edits"] = 1
		author = (params[:user_id].blank? ? nil : User.active.find(params[:user_id]))

		activity = Redmine::Activity::Fetcher.new(User.current, :project => project,
																 :with_subprojects => with_subprojects,
																 :author => author)
		activity.scope_select {|t| !params["show_#{t}"].nil?}
		#@activity.scope_select {:all}
		activity.scope = (author.nil? ? :default : :all) if activity.scope.empty?

		events = activity.events(date_from, date_to)

		#if events.empty?
		body[:events] = events
		body[:events_by_day] = events.group_by(&:event_date)
		body[:params] = params

	rescue ActiveRecord::RecordNotFound
		puts "Record not found!"
		#render_404
	end
  
	# Get all projects found with the plugin enabled or just the project specified
	def self.get_projects(project)
		projects = []
		if project.nil?
			p = EnabledModule.find(:all, :conditions => ["name = 'digest'"]).collect { |mod| mod.project_id }
			if p.length == 0
				puts "No projects were found in the environment or no projects have digest enabled."
				return
			end
			puts "There are %d projects that have the Digest module enabled:" % p.length
			condition = "id IN (" + p.join(",") + ")" 
			puts "   %s" % condition
			
			
			projects = Project.find(:all, :conditions => [condition])
			if projects.empty?
				puts "Could not find matching project."
			else
				puts "Found %d projects to check." % projects.length
			end
		else
			log "** Checking project '%s'" % project
			projects = Project.find(:all, 
				:conditions => ["id='%s' or identifier='%s'" % [project, project]])
			if projects.length == 0
				puts "The specified project '%s' was not found." % [project]
			end
		end
		return projects
	end
  
	def self.get_recipients(project)
		recipients = []
		members = Member.find(:all, :conditions => ["project_id = " + project[:id].to_s]).each { |m|
			recipients << User.find(m.user_id).mail
		}
		print "Recipients: "
		recipients.each { |r| print r + " " }
		puts
		return recipients
	end
  
	def self.digests(options={})
		start_default = Setting.plugin_digest[:start_default].to_i
		days_default = Setting.plugin_digest[:days_default].to_i
		days = options[:days].nil? ? days_default : options[:days].to_i
		start = options[:start].nil? ? start_default : options[:start].to_i
		puts
		log "====="
		log "Start: %d" % start
		log "Days : %d" % days
		results = []
		projects = get_projects(options[:project])
		projects.each do |project|
			log "Processing project '%s'..." % project.name
			
			body = {
				:project => project,
				:start => start,
				:days => days,
				:test_email => options[:test_email],
				:events => []
			}
			fill_events(project, body)
			if body[:events].empty?
			  message = "No events were found for project %s." % project.to_s
			  puts message
			  results << message
			  next
			end
			puts "Found %i events." % [body[:events].length]
			recipients = options[:test_email].nil? ? get_recipients(project) : options[:test_email]
			if recipients.empty?
				message = "No members were found for project %s." % project.to_s
				puts message
				results << message
				next
			end
			email = deliver_digest(project, recipients, body, start)
			period = body[:date_from] == body[:date_to]-1 ? format_date(body[:date_from]) : l(:label_date_from_to, :start => format_date(body[:date_from]), :end => format_date(body[:date_to]-1)).downcase
			message = "Sent digest: %s (%s)" % [email.subject, period]
			log message
			results << message
		end
		return results
	end
	
	def self.logger
		if RAILS_DEFAULT_LOGGER == nil
			#raise "No logger found"
		else
			return RAILS_DEFAULT_LOGGER
		end
		#ActionController::Base::logger
	end

	def self.log(info_message)
		puts info_message
		logger.info(info_message) unless logger.nil?
	end

end
