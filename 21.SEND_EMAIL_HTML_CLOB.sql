CREATE OR REPLACE PROCEDURE ABC_OWNER.send_email_html_clob (str_to IN VARCHAR2,  str_subject   IN VARCHAR2,   str_body      IN CLOB)
IS
    l_mail_conn   UTL_SMTP.connection;
    p_str_to      VARCHAR2(4000) := trim(str_to);
    pos number(10,0) := 0;
    i number(10,0) := 0;
    L_OFFSET number := 1;
    L_AMMOUNT number := 1900;
BEGIN
    --10.3.3.3    
    l_mail_conn := UTL_SMTP.open_connection ('10.3.3.3', 25);
    UTL_SMTP.helo (l_mail_conn, '10.3.3.3');
    UTL_SMTP.command (l_mail_conn, 'AUTH LOGIN');
    UTL_SMTP.command (
        l_mail_conn,
        UTL_RAW.cast_to_varchar2 (
            UTL_ENCODE.base64_encode (UTL_RAW.cast_to_raw ('u1'))));
    UTL_SMTP.command (
        l_mail_conn,
        UTL_RAW.cast_to_varchar2 (
            UTL_ENCODE.base64_encode (UTL_RAW.cast_to_raw ('password'))));
    UTL_SMTP.mail (l_mail_conn, 'u1@gmail.com');

      pos   := INSTR (p_str_to, ';', 1, 1);

      IF pos = 0
    THEN
        UTL_SMTP.rcpt (l_mail_conn, p_str_to);
    END IF;

       -- while there are chunks left, loop
      WHILE (pos != 0)
      LOOP
         UTL_SMTP.rcpt (l_mail_conn, SUBSTR (p_str_to, 1, pos-1));

         p_str_to        := SUBSTR (p_str_to, pos + 1, LENGTH (p_str_to));

         pos           := INSTR (p_str_to, ';', 1, 1);

         IF pos = 0
         THEN
            UTL_SMTP.rcpt (l_mail_conn, p_str_to);
         END IF;
      END LOOP;


    UTL_SMTP.open_data (l_mail_conn);
    UTL_SMTP.write_data (
        l_mail_conn,
        'Subject: =?UTF-8?Q?'
        || UTL_RAW.cast_to_varchar2(UTL_ENCODE.quoted_printable_encode (
                                        UTL_RAW.cast_to_raw (str_subject)))
        || '?='
        || UTL_TCP.crlf);
   UTL_SMTP.write_data (l_mail_conn, 'MIME-version: 1.0' || UTL_TCP.crlf);
    UTL_SMTP.write_data (
        l_mail_conn,
        'Content-Type: text/html;charset=utf-8' || UTL_TCP.crlf);
    UTL_SMTP.write_data (
        l_mail_conn,
        'Content-Transfer-Encoding: quoted-printable ' || UTL_TCP.crlf);

    UTL_SMTP.write_data (
        l_mail_conn,
           'Date: '
        || TO_CHAR (SYSDATE, 'DD-MON-YYYY HH24:MI:SS')
        || UTL_TCP.crlf);
    UTL_SMTP.write_data (l_mail_conn, 'To: ' || str_to || UTL_TCP.crlf);
    UTL_SMTP.write_data (
        l_mail_conn,
        'From: ' || 'u1@gmail.com' || UTL_TCP.crlf);

    UTL_SMTP.write_data (
        l_mail_conn,
           'Reply-To: '
        || 'u1@gmail.com'
        || UTL_TCP.crlf
        || UTL_TCP.crlf);

    WHILE L_OFFSET < DBMS_LOB.GETLENGTH(str_body) LOOP
        UTL_SMTP.write_raw_data (
        l_mail_conn,
        UTL_ENCODE.quoted_printable_encode (UTL_RAW.cast_to_raw (DBMS_LOB.SUBSTR(str_body,L_AMMOUNT,L_OFFSET))));
        L_OFFSET := L_OFFSET + L_AMMOUNT ;
        L_AMMOUNT := LEAST(1900,DBMS_LOB.GETLENGTH(str_body) - L_OFFSET);
    END LOOP;

    UTL_SMTP.close_data (l_mail_conn);

    UTL_SMTP.quit (l_mail_conn);
END send_email_html_clob;
/
