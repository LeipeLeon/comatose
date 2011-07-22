module Comatose
  class BaseController < ApplicationController
    unloadable

    before_filter :handle_authorization, :set_content_type
    after_filter :cache_cms_page

    # Render a specific page
    def show
      page_name, page_ext = get_page_path
      page = Page.find_by_path page_name
      status = nil
      if page.nil?
        status  = 404
        page    = Page.find_by_path '404'
      end
      # if it's still nil, well, send a 404 status
      if page.nil?
        render :nothing => true, :status => status
        #raise ActiveRecord::RecordNotFound.new("Comatose page not found ")
      else
        # Make the page access 'safe'
        @page = Comatose::PageWrapper.new(page)
        # For accurate uri creation, tell the page class which is the active mount point...
        Page.active_mount_info = get_active_mount_point(params[:index])
        render :text => page.to_html({'params' => params.stringify_keys}), :layout => get_page_layout, :status => status
      end
    end

  protected

    def handle_authorization
      if Comatose.config.authorization.is_a? Proc
        instance_eval &Comatose.config.authorization
      elsif Comatose.config.authorization.is_a? Symbol
        send(Comatose.config.authorization)
      elsif defined? authorize
        authorize
      else
        true
      end
    end

    def allow_page_cache?
      # You should have access to the @page being rendered
      true
    end

    # For use in the #show method... determines the current mount point
    def get_active_mount_point( index )
      Comatose.mount_points.each do |path_info|
        if path_info[:index] == index
          return path_info
        end
      end
      {:root=>"", :index=>index}
    end

    def get_page_path
      logger.debug "[**Comatose**]: get_page_path, params[:page] class: #{params[:page].class }"

      case params[:page]
      when Array
        page_name = params[:page].join("/")
      when NilClass
        page_name = ''
      else
        logger.debug "[**Comatose**]: get_page_path - params[:page] is an unrecognized type, may cause problems: #{params[:page].class}"
        page_name = params[:page].to_s
      end

      logger.debug "[**Comatose**]: got page_name: #{page_name}"


      page_ext = page_name.split('.')[1] unless page_name.empty?
      # TODO: Automatic support for page RSS feeds... ????
      if page_name.nil? or page_name.empty?
        if params[:index].blank?
          page_name = ''
        else
          page_name           = params[:index]
          params[:cache_path] = "#{request.fullpath}/index"
          page_name           = "#{params[:index]}/#{page_name}"
        end
      end
      return page_name, page_ext
    end

    # Returns a path to plugin layout, if it's unspecified, otherwise
    # a path to an application layout...
    def get_page_layout
      [params[:layout], @page.layout, 'comatose/base'].detect{ |shmerp| !shmerp.blank? }
    end

    # An after_filter implementing page caching if it's enabled, globally,
    # and is allowed by #allow_page_cache?
    def cache_cms_page
      unless Comatose.config.disable_caching or response.headers['Status'] == '404 Not Found'
        return unless params[:use_cache].to_s == 'true' and allow_page_cache?
        path = params[:cache_path] || request.request_uri
        begin
          # TODO: Don't cache pages rendering '404' content...
          self.class.cache_page( response.body, path )
        rescue
          logger.error "Comatose CMS Page Cache Exception: #{$!}"
        end
      end
    end

    # An after_filter that sets the HTTP header for Content-Type to
    # what's defined in Comatose.config.content_type. Defaults to utf-8.
    def set_content_type
      response.headers["Content-Type"] = "text/html; charset=#{Comatose.config.content_type}" unless Comatose.config.content_type.nil? or response.headers['Status'] == '404 Not Found'
    end

    COMATOSE_VIEW_PATH = File.join(Rails.root.to_s, 'vendor', 'plugins', 'comatose', 'views')
    ActionController::Base.append_view_path(COMATOSE_VIEW_PATH) unless ActionController::Base.view_paths.include?(COMATOSE_VIEW_PATH)

    # Include any, well, includes...
    Comatose.config.includes.each do |mod|
      mod_klass = if mod.is_a? String
        mod.constantize
      elsif mod.is_a? Symbol
        mod.to_s.classify.constantize
      else
        mod
      end
      include mod_klass
    end

    # Include any helpers...
    Comatose.config.helpers.each do |mod|
      mod_klass = if mod.is_a? String
        mod.constantize
      elsif mod.is_a? Symbol
        mod.to_s.classify.constantize
      else
        mod
      end
      helper mod_klass
    end
  end
end
