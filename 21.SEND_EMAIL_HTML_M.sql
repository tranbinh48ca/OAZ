CREATE OR REPLACE PROCEDURE send_email_html_m (STR_TO in varchar2, STR_SUBJECT in varchar2, STR_BODY in varchar2) is
  l_mail_conn   UTL_SMTP.connection;
  arrRecipients string_fnc.t_array;
begin
  
  l_mail_conn := UTL_SMTP.open_connection('10.50.50.50', 25); 
  UTL_SMTP.helo(l_mail_conn, '10.50.50.50')  
  utl_smtp.command( l_mail_conn, 'AUTH LOGIN');
  utl_smtp.command( l_mail_conn, utl_raw.cast_to_varchar2( utl_encode.base64_encode( utl_raw.cast_to_raw( 'u1' ))) );
  utl_smtp.command( l_mail_conn, utl_raw.cast_to_varchar2( utl_encode.base64_encode( utl_raw.cast_to_raw( 'abc123' ))) );
  UTL_SMTP.mail(l_mail_conn, 'u1@abc.vn');
  arrRecipients := string_fnc.split(STR_TO,',');
  for i in 1..arrRecipients.count LOOP
    UTL_SMTP.rcpt(l_mail_conn, arrRecipients(i));
  end loop;

  UTL_SMTP.open_data(l_mail_conn);

  --UTL_SMTP.write_data(l_mail_conn, 'Date: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') || UTL_TCP.crlf);
  UTL_SMTP.write_data(l_mail_conn, 'To: ' || STR_TO || UTL_TCP.crlf);
  UTL_SMTP.write_data(l_mail_conn, 'From: ' || 'u1@abc.vn' || UTL_TCP.crlf);
  UTL_SMTP.write_data(l_mail_conn, 'Subject: ' || STR_SUBJECT || UTL_TCP.crlf);
  UTL_SMTP.write_data(l_mail_conn, 'Reply-To: ' || 'u1@abc.vn' || UTL_TCP.crlf || UTL_TCP.crlf);

  UTL_SMTP.write_data(l_mail_conn, STR_BODY || UTL_TCP.crlf || UTL_TCP.crlf);
  UTL_SMTP.close_data(l_mail_conn);

  UTL_SMTP.quit(l_mail_conn);
END send_email_html_m;
/
