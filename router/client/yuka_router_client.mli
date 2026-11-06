val start :
  ?lazy_entries:Yuka_client.lazy_entry list -> Yuka.Client.entry list -> unit
(** [start entries] starts the islands with [Yuka_client.start entries] and
    takes over navigation:

    - A left click on an [<a href>] goes through [navigate] unless: the event
      is already prevented, a modifier key is down, the link has a [target]
      other than [_self], a [download] attribute or a [data-yuka-reload]
      attribute, the URL is on another origin, or the URL differs from the
      current one only by its fragment.
    - [popstate] loads the entry's URL without pushing history.

    [Yuka.Browser.navigate] does [navigate] after [start], also after each
    navigation.

    Calling [start] again is safe: the listeners are not added twice. *)

val navigate : string -> unit
(** [navigate url] loads [url] with the header [Yuka-Navigate: 1], stops the
    islands, replaces the content of [<body>] and [document.title] with those
    of the response, starts the islands again, pushes a history entry (after
    the page loaded) and scrolls to the fragment or to the top. A navigation
    started while another one loads aborts the first. If the request fails,
    it does [location.assign url]. Before [start], it does
    [location.assign url]. *)
