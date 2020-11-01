package WWW::PipeViewer::InitialData;

use utf8;
use 5.014;
use warnings;

=head1 NAME

WWW::PipeViewer::InitialData - Extract initial data.

=head1 SYNOPSIS

    use WWW::PipeViewer;
    my $obj = WWW::PipeViewer->new(%opts);

    my $results   = $obj->yt_search(q => $keywords);
    my $playlists = $obj->yt_channel_playlists($channel_ID);

=head1 SUBROUTINES/METHODS

=cut

sub _time_to_seconds {
    my ($time) = @_;

    my ($hours, $minutes, $seconds) = (0, 0, 0);

    if ($time =~ /(\d+):(\d+):(\d+)/) {
        ($hours, $minutes, $seconds) = ($1, $2, $3);
    }
    elsif ($time =~ /(\d+):(\d+)/) {
        ($minutes, $seconds) = ($1, $2);
    }
    elsif ($time =~ /(\d+)/) {
        $seconds = $1;
    }

    $hours * 3600 + $minutes * 60 + $seconds;
}

sub _human_number_to_int {
    my ($text) = @_;

    if ($text =~ /([\d,.]+)/) {
        my $v = $1;
        $v =~ tr/.,//d;
        return $v;
    }

    return 0;
}

sub _thumbnail_quality {
    my ($width) = @_;

    $width // return 'medium';

    if ($width == 1280) {
        return "maxres";
    }

    if ($width == 640) {
        return "sddefault";
    }

    if ($width == 480) {
        return 'high';
    }

    if ($width == 320) {
        return 'medium';
    }

    if ($width == 120) {
        return 'default';
    }

    if ($width <= 120) {
        return 'small';
    }

    if ($width <= 176) {
        return 'medium';
    }

    if ($width <= 480) {
        return 'high';
    }

    if ($width <= 640) {
        return 'sddefault';
    }

    if ($width <= 1280) {
        return "maxres";
    }

    return 'medium';
}

sub _fix_url_protocol {
    my ($url) = @_;

    $url // return undef;

    if ($url =~ m{^https://}) {    # ok
        return $url;
    }
    if ($url =~ s{^.*?//}{}) {
        return "https://" . $url;
    }
    if ($url =~ /^\w+\./) {
        return "https://" . $url;
    }

    return $url;
}

sub _unscramble {
    my ($str) = @_;

    my $i = my $l = length($str);

    $str =~ s/(.)(.{$i})/$2$1/sg while (--$i > 0);
    $str =~ s/(.)(.{$i})/$2$1/sg while (++$i < $l);

    return $str;
}

sub _extract_youtube_mix {
    my ($self, $data) = @_;

    my $info   = eval { $data->{callToAction}{watchCardHeroVideoRenderer} } || return;
    my $header = eval { $data->{header}{watchCardRichHeaderRenderer} };

    my %mix;

    $mix{type} = 'playlist';

    $mix{title} =
      eval    { $header->{title}{runs}[0]{text} }
      // eval { $info->{accessibility}{accessibilityData}{label} }
      // eval { $info->{callToActionButton}{callToActionButtonRenderer}{label}{runs}[0]{text} } // 'Youtube Mix';

    $mix{playlistId} = eval { $info->{navigationEndpoint}{watchEndpoint}{playlistId} } || return;

    $mix{playlistThumbnail} = eval { _fix_url_protocol($header->{avatar}{thumbnails}[0]{url}) }
      // eval { _fix_url_protocol($info->{heroImage}{collageHeroImageRenderer}{leftThumbnail}{thumbnails}[0]{url}) };

    $mix{description} = _extract_description({title => $info});

    $mix{author}   = eval { $header->{title}{runs}[0]{text} }                              // "YouTube";
    $mix{authorId} = eval { $header->{titleNavigationEndpoint}{browseEndpoint}{browseId} } // "youtube";

    return \%mix;
}

sub _extract_author_name {
    my ($info) = @_;
    eval { $info->{longBylineText}{runs}[0]{text} } // eval { $info->{shortBylineText}{runs}[0]{text} };
}

sub _extract_video_id {
    my ($info) = @_;
    eval { $info->{videoId} } || eval { $info->{navigationEndpoint}{watchEndpoint}{videoId} } || undef;
}

sub _extract_length_seconds {
    my ($info) = @_;
    eval { $info->{lengthSeconds} }
      || _time_to_seconds(eval { $info->{thumbnailOverlays}[0]{thumbnailOverlayTimeStatusRenderer}{text}{runs}[0]{text} } // 0)
      || _time_to_seconds(eval { $info->{lengthText}{runs}[0]{text} // 0 });
}

sub _extract_published_text {
    my ($info) = @_;

    my $text = eval { $info->{publishedTimeText}{runs}[0]{text} } || return undef;

    if ($text =~ /(\d+) (\w+)/) {
        return "$1 $2";
    }

    return $text;
}

sub _extract_channel_id {
    my ($info) = @_;
    eval      { $info->{channelId} }
      // eval { $info->{shortBylineText}{runs}[0]{navigationEndpoint}{browseEndpoint}{browseId} }
      // eval { $info->{navigationEndpoint}{browseEndpoint}{browseId} };
}

sub _extract_view_count_text {
    my ($info) = @_;
    eval { $info->{shortViewCountText}{runs}[0]{text} };
}

sub _extract_thumbnails {
    my ($info) = @_;
    eval {
        [
         map {
             my %thumb = %$_;
             $thumb{quality} = _thumbnail_quality($thumb{width});
             $thumb{url}     = _fix_url_protocol($thumb{url});
             \%thumb;
         } @{$info->{thumbnail}{thumbnails}}
        ]
    };
}

sub _extract_playlist_thumbnail {
    my ($info) = @_;
    eval {
        _fix_url_protocol(
                         (
                          grep { _thumbnail_quality($_->{width}) =~ /medium|high/ }
                            @{$info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}}
                         )[0]{url} // $info->{thumbnailRenderer}{playlistVideoThumbnailRenderer}{thumbnail}{thumbnails}[0]{url}
        );
    } // eval {
        _fix_url_protocol((grep { _thumbnail_quality($_->{width}) =~ /medium|high/ } @{$info->{thumbnail}{thumbnails}})[0]{url}
                          // $info->{thumbnail}{thumbnails}[0]{url});
    };
}

sub _extract_title {
    my ($info) = @_;
    eval { $info->{title}{runs}[0]{text} } // eval { $info->{title}{accessibility}{accessibilityData}{label} };
}

sub _extract_description {
    my ($info) = @_;

    # FIXME: this is not the video description
    eval { $info->{title}{accessibility}{accessibilityData}{label} };
}

sub _extract_view_count {
    my ($info) = @_;
    _human_number_to_int(eval { $info->{viewCountText}{runs}[0]{text} } || 0);
}

sub _extract_video_count {
    my ($info) = @_;
    _human_number_to_int(   eval { $info->{videoCountShortText}{runs}[0]{text} }
                         || eval { $info->{videoCountText}{runs}[0]{text} }
                         || 0);
}

sub _extract_subscriber_count {
    my ($info) = @_;

    # FIXME: convert dd.dK into ddd00
    _human_number_to_int(eval { $info->{subscriberCountText}{runs}[0]{text} } || 0);
}

sub _extract_playlist_id {
    my ($info) = @_;
    eval { $info->{playlistId} };
}

sub _extract_itemSection_entry {
    my ($self, $data, %args) = @_;

    ref($data) eq 'HASH' or return;

    # Album
    if ($args{type} eq 'all' and exists $data->{horizontalCardListRenderer}) {    # TODO
        return;
    }

    # Video
    if (exists($data->{compactVideoRenderer}) or exists($data->{playlistVideoRenderer})) {

        my %video;
        my $info = $data->{compactVideoRenderer} // $data->{playlistVideoRenderer};

        $video{type} = 'video';

        # Deleted video
        if (defined(eval { $info->{isPlayable} }) and not $info->{isPlayable}) {
            return;
        }

        $video{videoId}         = _extract_video_id($info) // return;
        $video{title}           = _extract_title($info)    // return;
        $video{lengthSeconds}   = _extract_length_seconds($info) || return;
        $video{author}          = _extract_author_name($info);
        $video{authorId}        = _extract_channel_id($info);
        $video{publishedText}   = _extract_published_text($info);
        $video{viewCountText}   = _extract_view_count_text($info);
        $video{videoThumbnails} = _extract_thumbnails($info);
        $video{description}     = _extract_description($info);
        $video{viewCount}       = _extract_view_count($info);

        return \%video;
    }

    # Playlist
    if ($args{type} ne 'video' and exists $data->{compactPlaylistRenderer}) {

        my %playlist;
        my $info = $data->{compactPlaylistRenderer};

        $playlist{type} = 'playlist';

        $playlist{title}             = _extract_title($info)       // return;
        $playlist{playlistId}        = _extract_playlist_id($info) // return;
        $playlist{author}            = _extract_author_name($info);
        $playlist{authorId}          = _extract_channel_id($info);
        $playlist{videoCount}        = _extract_video_count($info);
        $playlist{playlistThumbnail} = _extract_playlist_thumbnail($info);
        $playlist{description}       = _extract_description($info);

        return \%playlist;
    }

    # Channel
    if ($args{type} ne 'video' and exists $data->{compactChannelRenderer}) {

        my %channel;
        my $info = $data->{compactChannelRenderer};

        $channel{type} = 'channel';

        $channel{author}           = _extract_title($info)      // return;
        $channel{authorId}         = _extract_channel_id($info) // return;
        $channel{subCount}         = _extract_subscriber_count($info);
        $channel{videoCount}       = _extract_video_count($info);
        $channel{authorThumbnails} = _extract_thumbnails($info);
        $channel{description}      = _extract_description($info);

        return \%channel;
    }

    return;
}

sub _parse_itemSection {
    my ($self, $entry, %args) = @_;

    eval { ref($entry->{contents}) eq 'ARRAY' } || return;

    my @results;

    foreach my $entry (@{$entry->{contents}}) {

        my $item = $self->_extract_itemSection_entry($entry, %args);

        if (defined($item) and ref($item) eq 'HASH') {
            push @results, $item;
        }
    }

    if (@results and exists $entry->{continuations} and ref($entry->{continuations}) eq 'ARRAY') {

        my $token = eval { $entry->{continuations}[0]{nextContinuationData}{continuation} };

        if (defined($token)) {
            push @results,
              scalar {
                      type  => 'nextpage',
                      token => "ytplaylist:$args{type}:$token",
                     };
        }
    }

    return @results;
}

sub _extract_sectionList_results {
    my ($self, $data, %args) = @_;

    eval { ref($data->{contents}) eq 'ARRAY' } or return;

    my @results;

    foreach my $entry (@{$data->{contents}}) {

        # Playlists
        if (eval { ref($entry->{shelfRenderer}{content}{verticalListRenderer}{items}) eq 'ARRAY' }) {
            push @results,
              $self->_parse_itemSection({contents => $entry->{shelfRenderer}{content}{verticalListRenderer}{items}}, %args);
        }

        # Playlist videos
        if (eval { ref($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}{contents}) eq 'ARRAY' }) {
            push @results,
              $self->_parse_itemSection($entry->{itemSectionRenderer}{contents}[0]{playlistVideoListRenderer}, %args);
            next;
        }

        # YouTube Mix
        if ($args{type} eq 'all' and exists $entry->{universalWatchCardRenderer}) {

            my $mix = $self->_extract_youtube_mix($entry->{universalWatchCardRenderer});

            if (defined($mix)) {
                push(@results, $mix);
            }
        }

        # Video results
        if (exists $entry->{itemSectionRenderer}) {
            push @results, $self->_parse_itemSection($entry->{itemSectionRenderer}, %args);
        }

        # Continuation page
        if (exists $entry->{continuationItemRenderer}) {

            my $info  = $entry->{continuationItemRenderer};
            my $token = eval { $info->{continuationEndpoint}{continuationCommand}{token} };

            if (defined($token)) {
                push @results,
                  scalar {
                          type  => 'nextpage',
                          token => "ytsearch:$args{type}:$token",
                         };
            }
        }
    }

    return @results;
}

sub _add_author_to_results {
    my ($self, $data, $results, %args) = @_;

    my $header = eval { $data->{header}{c4TabbedHeaderRenderer} } // eval { $data->{metadata}{channelMetadataRenderer} };

    my $channel_id   = eval { $header->{channelId} } // eval { $header->{externalId} };
    my $channel_name = eval { $header->{title} };

    foreach my $result (@$results) {
        if (ref($result) eq 'HASH') {
            $result->{author}   = $channel_name if defined($channel_name);
            $result->{authorId} = $channel_id   if defined($channel_id);
        }
    }

    return 1;
}

sub _extract_channel_uploads {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results(
        eval {
            $data->{contents}{singleColumnBrowseResultsRenderer}{tabs}[1]{tabRenderer}{content}{sectionListRenderer};
        },
        %args
                                                     );
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_channel_playlists {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results(
        eval {
            $data->{contents}{singleColumnBrowseResultsRenderer}{tabs}[2]{tabRenderer}{content}{sectionListRenderer};
        },
        %args
                                                     );
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _extract_playlist_videos {
    my ($self, $data, %args) = @_;

    my @results = $self->_extract_sectionList_results(
        eval {
            $data->{contents}{singleColumnBrowseResultsRenderer}{tabs}[0]{tabRenderer}{content}{sectionListRenderer};
        },
        %args
                                                     );
    $self->_add_author_to_results($data, \@results, %args);
    return @results;
}

sub _get_initial_data {
    my ($self, $url) = @_;

    my $content = $self->lwp_get($url);

    if ($content =~ m{<div id="initial-data"><!--(.*?)--></div>}is) {
        my $json = $1;
        my $hash = $self->parse_utf8_json_string($json);
        return $hash;
    }

    return;
}

sub _channel_data {
    my ($self, $channel, %args) = @_;

    state $yv_utils = WWW::PipeViewer::Utils->new();

    my $url = $self->get_m_youtube_url;

    if ($yv_utils->is_channelID($channel)) {
        $url .= "/channel/$channel/$args{type}";
    }
    else {
        $url .= "/c/$channel/$args{type}";
    }

    if (defined(my $sort = $args{sort_by})) {
        if ($sort eq 'popular') {
            $url .= "?sort=p";
        }
        elsif ($sort eq 'old') {
            $url .= "?sort=da";
        }
    }

    ($url, $self->_get_initial_data($url));
}

sub _prepare_results_for_return {
    my ($self, $results, %args) = @_;

    (defined($results) and ref($results) eq 'ARRAY') || return;

    my @results = @$results;

    if (@results and $results[-1]{type} eq 'nextpage') {

        my $nextpage = pop(@results);

        if (defined($nextpage->{token}) and @results) {

            if ($self->get_debug) {
                say STDERR ":: Returning results with a continuation page token...";
            }

            return {
                    url     => $args{url},
                    results => {
                                entries      => \@results,
                                continuation => $nextpage->{token},
                               },
                   };
        }
    }

    my $url = $args{url};

    if ($url =~ m{^https://m\.youtube\.com}) {
        $url = undef;
    }

    return {
            url     => $url,
            results => \@results,
           };
}

=head2 yt_search(q => $keyword, %args)

Search for videos given a keyword (uri-escaped).

=cut

sub yt_search {
    my ($self, %args) = @_;

    my $url = $self->get_m_youtube_url . "/results?search_query=$args{q}";

    $args{type} //= 'video';

    # FIXME:
    #   Currently, only one parameter per search is supported.
    #   Would be nice to figure it out how to combine multiple parameters into one.

    if ($args{type} eq 'video') {

        if (defined(my $duration = $self->get_videoDuration)) {
            if ($duration eq 'long') {
                $url .= "&sp=EgQQARgC";
            }
            elsif ($duration eq 'short') {
                $url .= "&sp=EgQQARgB";
            }
        }

        if (defined(my $date = $self->get_date)) {
            if ($date eq 'hour') {
                $url .= "&sp=EgQIARAB";
            }
            elsif ($date eq 'today') {
                $url .= "&sp=EgQIAhAB";
            }
            elsif ($date eq 'week') {
                $url .= "&sp=EgQIAxAB";
            }
            elsif ($date eq 'month') {
                $url .= "&sp=EgQIBBAB";
            }
            elsif ($date eq 'year') {
                $url .= "&sp=EgQIBRAB";
            }
        }

        if (defined(my $order = $self->get_order)) {
            if ($order eq 'upload_date') {
                $url .= "&sp=CAISAhAB";
            }
            elsif ($order eq 'view_count') {
                $url .= "&sp=CAMSAhAB";
            }
            elsif ($order eq 'rating') {
                $url .= "&sp=CAESAhAB";
            }
        }

        if (defined(my $license = $self->get_videoLicense)) {
            if ($license eq 'creative_commons') {
                $url .= "&sp=EgIwAQ%253D%253D";
            }
        }

        if (defined(my $vd = $self->get_videoDefinition)) {
            if ($vd eq 'high') {
                $url .= "&sp=EgIgAQ%253D%253D";
            }
        }

        if (defined(my $vc = $self->get_videoCaption)) {
            if ($vc eq 'true' or $vc eq '1') {
                $url .= "&sp=EgIoAQ%253D%253D";
            }
        }

        if (defined(my $vd = $self->get_videoDimension)) {
            if ($vd eq '3d') {
                $url .= "&sp=EgI4AQ%253D%253D";
            }
        }
    }

    if ($args{type} eq 'video') {
        if ($url !~ /&sp=/) {
            $url .= "&sp=EgIQAQ%253D%253D";
        }
    }
    elsif ($args{type} eq 'playlist') {
        $url .= "&sp=EgIQAw%253D%253D";
    }
    elsif ($args{type} eq 'channel') {
        $url .= "&sp=EgIQAg%253D%253D";
    }
    elsif ($args{type} eq 'movie') {    # TODO: implement support for movies
        $url .= "&sp=EgIQBA%253D%253D";
    }

    my $hash    = $self->_get_initial_data($url) // return;
    my @results = $self->_extract_sectionList_results(eval { $hash->{contents}{sectionListRenderer} }, %args);

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_uploads($channel, %args)

Latest uploads for a given channel ID or username.

=cut

sub yt_channel_uploads {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'videos');

    $hash // return;

    my @results = $self->_extract_channel_uploads($hash, %args, type => 'video');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_channel_playlists($channel, %args)

Playlists for a given channel ID or username.

=cut

sub yt_channel_playlists {
    my ($self, $channel, %args) = @_;
    my ($url, $hash) = $self->_channel_data($channel, %args, type => 'playlists');

    $hash // return;

    my @results = $self->_extract_channel_playlists($hash, %args, type => 'playlist');
    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_videos($playlist_id, %args)

Videos from a given playlist ID.

=cut

sub yt_playlist_videos {
    my ($self, $playlist_id, %args) = @_;

    my $url  = $self->get_m_youtube_url . "/playlist?list=$playlist_id";
    my $hash = $self->_get_initial_data($url) // return;

    my @results = $self->_extract_sectionList_results(
        eval {
            $hash->{contents}{singleColumnBrowseResultsRenderer}{tabs}[0]{tabRenderer}{content}{sectionListRenderer};
        },
        %args,
        type => 'video'
                                                     );

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_playlist_next_page($url, $token, %args)

Load more items from a playlist, given a continuation token.

=cut

sub yt_playlist_next_page {
    my ($self, $url, $token, %args) = @_;

    my $request_url = $url;

    if ($request_url =~ /\?/) {
        $request_url .= "&ctoken=$token";
    }
    else {
        $request_url .= "?ctoken=$token";
    }

    #say $url;

    #my $url  = $self->get_m_youtube_url . "/playlist?ctoken=$token";
    my $hash = $self->_get_initial_data($request_url) // return;

    #use Data::Dump qw(pp);
    #pp $hash;

    my @results = $self->_parse_itemSection(
                                            eval      { $hash->{continuationContents}{playlistVideoListContinuation} }
                                              // eval { $hash->{continuationContents}{itemSectionContinuation} },
                                            %args
                                           );

    $self->_add_author_to_results($hash, \@results, %args);

    $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head2 yt_search_next_page($url, $token, %args)

Load more search results, given a continuation token.

=cut

sub yt_search_next_page {
    my ($self, $url, $token, %args) = @_;

    my %request = (
                   "context" => {
                              "client" => {
                                  "browserName"      => "Firefox",
                                  "browserVersion"   => "82.0",
                                  "clientFormFactor" => "LARGE_FORM_FACTOR",
                                  "clientName"       => "MWEB",
                                  "clientVersion"    => "2.20201030.01.00",
                                  "deviceMake"       => "generic",
                                  "deviceModel"      => "android 11.0",
                                  "gl"               => "US",
                                  "hl"               => "en",
                                  "mainAppWebInfo"   => {
                                                       "graftUrl" => "https://m.youtube.com/results?search_query=youtube"
                                                      },
                                  "osName"             => "Android",
                                  "osVersion"          => "10",
                                  "platform"           => "TABLET",
                                  "playerType"         => "UNIPLAYER",
                                  "screenDensityFloat" => 1,
                                  "screenHeightPoints" => 420,
                                  "screenPixelDensity" => 1,
                                  "screenWidthPoints"  => 1442,
                                  "userAgent" => "Mozilla/5.0 (Android 10; Tablet; rv:82.0) Gecko/82.0 Firefox/82.0,gzip(gfe)",
                                  "userInterfaceTheme" => "USER_INTERFACE_THEME_LIGHT",
                                  "utcOffsetMinutes"   => 0,
                              },
                              "request" => {
                                            "consistencyTokenJars"    => [],
                                            "internalExperimentFlags" => [],
                                           },
                              "user" => {}
                   },
                   "continuation" => $token,
                  );

    my $content = $self->post_as_json(
                                      $self->get_m_youtube_url
                                        . _unscramble('o/ebseky?u1ri//hvcuyta=e')
                                        . _unscramble('1HUCiSlOalFEcYQSS8_9q1LW4y8JAwI2zT_qA_G'),
                                      \%request
                                     ) // return;

    my $hash = $self->parse_json_string($content);

    my @results = $self->_extract_sectionList_results(
        {
         contents => eval {
             $hash->{onResponseReceivedCommands}[0]{appendContinuationItemsAction}{continuationItems};
           } // undef
        },
        %args
                                                     );

    return $self->_prepare_results_for_return(\@results, %args, url => $url);
}

=head1 AUTHOR

Trizen, C<< <echo dHJpemVuQHByb3Rvbm1haWwuY29tCg== | base64 -d> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::PipeViewer::InitialData


=head1 LICENSE AND COPYRIGHT

Copyright 2013-2015 Trizen.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;    # End of WWW::PipeViewer::InitialData