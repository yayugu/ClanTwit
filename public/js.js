$(function(){
  $("#tweet-form").submit(function(e){
    $('#after-tweet-message').empty().append("<img src=load.gif /> 送信中...");
    $.post(
      "do_tweet",
      {'tweet_type': $('input[name="tweet_type"]:checked').val(),
       'tweet': $('textarea[name="tweet"]').val()
      },
      function(data, status){
        $('#after-tweet-message')
          .empty().append(data);
      },
      'html'
    );
  });

  $('#tweet').charCount();
});
