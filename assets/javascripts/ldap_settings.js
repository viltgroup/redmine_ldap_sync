/*
 * Redmine LDAP Sync - JavaScript
 * Updated for Rails 7 / Turbo / Stimulus compatibility
 */

(function() {
  "use strict";

  function show_options(elem, ambit) {
    var selected = $(elem).val();
    var prefix = '#ldap_attributes div.' + ambit;
    if (selected !== '') {
      $(prefix + '.' + selected).show();
      $(prefix + ':not(.' + selected + ')').hide();
    } else {
      $(prefix).hide();
    }
  }

  function show_dyngroups_ttl(elem) {
    if ($(elem).val() == 'enabled_with_ttl')
      $('#dyngroups-cache-ttl').show();
    else
      $('#dyngroups-cache-ttl').hide();
  }

  function initSettings() {
    if ($('#ldap_setting_group_membership').length) {
      show_options($('#ldap_setting_group_membership'), 'membership');
      $('#ldap_setting_group_membership')
        .off('change.ldap keyup.ldap')
        .on('change.ldap keyup.ldap', function() { show_options(this, 'membership'); });
    }

    if ($('#ldap_setting_nested_groups').length) {
      show_options($('#ldap_setting_nested_groups'), 'nested');
      $('#ldap_setting_nested_groups')
        .off('change.ldap keyup.ldap')
        .on('change.ldap keyup.ldap', function() { show_options(this, 'nested'); });
    }

    if ($('#base_settings').length) {
      $('#base_settings').off('change.ldap keyup.ldap').on('change.ldap keyup.ldap', function() {
        var id = $(this).val();
        if (typeof base_settings === 'undefined' || !base_settings[id]) return;
        var hash = base_settings[id];
        for (var k in hash) if (hash.hasOwnProperty(k)) {
          if (k === 'name' || hash[k] === $('#ldap_setting_' + k).val()) continue;
          $('#ldap_setting_' + k).val(hash[k]).change();
        }
      });
    }

    if ($('#ldap_setting_dyngroups').length) {
      show_dyngroups_ttl($('#ldap_setting_dyngroups'));
      $('#ldap_setting_dyngroups')
        .off('change.ldap keyup.ldap')
        .on('change.ldap keyup.ldap', function() { show_dyngroups_ttl(this); });
    }

    $('form[id^="edit_ldap_setting"]')
      .off('submit.ldap')
      .on('submit.ldap', function() {
        var current_tab = $('a[id^="tab-"].selected').attr('id');
        if (current_tab) {
          current_tab = current_tab.substring(4);
          $(this).find('input[name="tab"]').remove();
          $(this).append('<input type="hidden" name="tab" value="' + current_tab + '">');
        }
      });

    // Kezdeti állapot beállítása ha a Schedule tab aktív
    updateAllScheduleUIs();
  }

  // Event delegation - a #commit-test dinamikusan renderelődik tab váltáskor
  // ezért nem közvetlen bind kell, hanem document szintű delegálás
  $(document).off('click.ldaptest').on('click.ldaptest', '#commit-test', function(e) {
    e.preventDefault();
    e.stopPropagation();

    var $btn = $(this);
    var url = $btn.data('test-url');

    if (!url) {
      console.error('LDAP Sync: missing data-test-url on #commit-test');
      return;
    }

    var formData = $('form[id^="edit_ldap_setting"]').serialize();
    var csrfMeta = document.querySelector('meta[name="csrf-token"]');
    var csrfToken = csrfMeta ? csrfMeta.getAttribute('content') : '';

    $('#test-result').text('Running...');
    $btn.prop('disabled', true);

    fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-CSRF-Token': csrfToken,
        'Accept': 'text/plain',
        'X-Requested-With': 'XMLHttpRequest'
      },
      body: formData
    })
    .then(function(response) { return response.text(); })
    .then(function(data) {
      $('#test-result').text(data || 'No result');
    })
    .catch(function(err) {
      $('#test-result').text('Error: ' + err.message);
    })
    .finally(function() {
      $btn.prop('disabled', false);
    });
  });

  // Enter billentyű a test mezőkben
  $(document).off('keydown.ldaptest').on('keydown.ldaptest', 'input[name^="ldap_test"]', function(e) {
    if (e.which == 13) {
      $('#commit-test').click();
      e.preventDefault();
    }
  });


  // ── Schedule tab logika - event delegation (Turbo kompatibilis) ──
  // The tab has one form per automatic synchronization mode (database / saved locally),
  // so every lookup is scoped to the .ldap-schedule-form it belongs to.


  function updateMinuteSelector($form, freq) {
    var $sel = $form.find('.schedule-minute');
    if (!$sel.length) return;
    var current = $sel.val();

    if (freq === 'hourly' || freq === 'daily') {
      // 0-59
      $sel.empty();
      for (var i = 0; i < 60; i++) {
        var label = (i < 10 ? '0' : '') + i;
        $sel.append($('<option>', {value: i, text: label}));
      }
    }
    // Próbáljuk visszaállítani az előző értéket
    if ($sel.find('option[value="' + current + '"]').length) {
      $sel.val(current);
    }
  }

  function updateScheduleUI($form) {
    var $freq = $form.find('.schedule-frequency');
    if (!$freq.length) return;
    var freq = $freq.val();

    // 15 és 30 percnél nincs időpont beállítás
    if (freq === 'every_15_min' || freq === 'every_30_min') {
      $form.find('.schedule-time-options').hide();
    } else {
      $form.find('.schedule-time-options').show();
    }

    // Óránként: csak percválasztó, az óraválasztót elrejtjük
    if (freq === 'hourly') {
      $form.find('.schedule-hour-select').hide();
      $form.find('.schedule-hour-colon').hide();
    } else {
      $form.find('.schedule-hour-select').show();
      $form.find('.schedule-hour-colon').show();
    }

    var hints = {
      'every_15_min': 'Runs every 15 minutes',
      'every_30_min': 'Runs every 30 minutes',
      'hourly':       'Runs every hour at the selected minute',
      'daily':        'Runs once a day at the selected time'
    };
    $form.find('.schedule-time-hint').text(hints[freq] || '');
    updateMinuteSelector($form, freq);
  }

  function updateAllScheduleUIs() {
    $('.ldap-schedule-form').each(function() { updateScheduleUI($(this)); });
  }

  // Event delegation - Turbo-barát
  $(document).off('change.schedule_enabled').on('change.schedule_enabled', '.schedule-enabled', function() {
    var $options = $(this).closest('.ldap-schedule-form').find('.schedule-options');
    if ($(this).is(':checked')) {
      $options.slideDown(200);
    } else {
      $options.slideUp(200);
    }
  });

  $(document).off('change.schedule_freq').on('change.schedule_freq', '.schedule-frequency', function() {
    updateScheduleUI($(this).closest('.ldap-schedule-form'));
  });

  // Run now gomb
  $(document).off('click.runnow').on('click.runnow', '#run-now-btn', function(e) {
    e.preventDefault();
    var $btn = $(this);
    var url  = $btn.data('url');
    var csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

    $('#run-now-output').text('');
    $('#run-now-result').show();
    $('#run-now-output').text('⏳ Starting sync...');
    $('#run-now-spinner').show();
    $btn.prop('disabled', true);

    fetch(url, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'text/plain',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(function(r) { return r.text(); })
    .then(function(data) {
      $('#run-now-output').text(data);
    })
    .catch(function(err) {
      $('#run-now-output').text('Error: ' + err.message);
    })
    .finally(function() {
      $('#run-now-spinner').hide();
      $btn.prop('disabled', false);
    });
  });


  // Tab váltás logika - Schedule tabnál elrejtjük a fő form Save gombját
  $(document).off('click.tabswitch').on('click.tabswitch', '.tabs a', function() {
    var tabName = $(this).attr('id').replace('tab-', '');
    // Tab tartalmak váltása
    $('.tab-content').hide();
    $('#tab-content-' + tabName).show();
    // Save gomb láthatósága
    if (tabName === 'Schedule') {
      $('#main-form-submit').hide();
    } else {
      $('#main-form-submit').show();
    }
    // Schedule UI frissítés ha Schedule tabra váltunk
    if (tabName === 'Schedule') {
      updateAllScheduleUIs();
    }
    // Tab kiválasztás jelölése
    $('.tabs a').removeClass('selected');
    $(this).addClass('selected');
    return false;
  });

  // Turbo és hagyományos ready - mindkettő
  document.addEventListener('turbo:load', initSettings);
  document.addEventListener('turbo:render', initSettings);
  $(document).ready(initSettings);

})();
