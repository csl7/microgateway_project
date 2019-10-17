/*
 *  Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 *  WSO2 Inc. licenses this file to you under the Apache License,
 *  Version 2.0 (the "License"); you may not use this file except
 *  in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

package org.wso2.micro.gateway.tests.util.HTTP2Client;

import io.netty.bootstrap.Bootstrap;
import io.netty.channel.Channel;
import io.netty.channel.ChannelOption;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.nio.NioSocketChannel;
import io.netty.handler.codec.http.DefaultFullHttpRequest;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpHeaderValues;
import io.netty.handler.codec.http.HttpScheme;
import io.netty.handler.codec.http2.Http2SecurityUtil;
import io.netty.handler.codec.http2.HttpConversionUtil;
import io.netty.handler.ssl.ApplicationProtocolConfig;
import io.netty.handler.ssl.ApplicationProtocolNames;
import io.netty.handler.ssl.OpenSsl;
import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslProvider;
import io.netty.handler.ssl.SupportedCipherSuiteFilter;
import io.netty.handler.ssl.util.InsecureTrustManagerFactory;
import io.netty.util.AsciiString;
import io.netty.util.CharsetUtil;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import javax.net.ssl.SSLException;
import java.util.concurrent.TimeUnit;

import static io.netty.buffer.Unpooled.wrappedBuffer;
import static io.netty.handler.codec.http.HttpMethod.*;
import static io.netty.handler.codec.http.HttpVersion.HTTP_1_1;

/**
 * An HTTP2 client that allows you to send HTTP2 frames to a server. Inbound and outbound frames are
 * logged. When run from the command-line, sends a single HEADERS frame to the server and gets back
 * a response.
 */
public final class Http2ClientRequest {

    static final String HOST = System.getProperty("host", "127.0.0.1");
    static final String URL = System.getProperty("url", "/pizzashack/1.0.0/menu");
    static final String URLDATA = System.getProperty("url2data", "test data!");
    private static final Log log = LogFactory.getLog(Http2ClientRequest.class);
    static boolean SSL;
    static int PORT;
    static String token;

    public Http2ClientRequest(boolean ssl, int port, String token) {
        Http2ClientRequest.SSL = ssl;
        Http2ClientRequest.PORT = port;
        Http2ClientRequest.token = token;
    }

    public static void main(String[] args) throws Exception {
        Http2ClientRequest http2ClientRequest = new Http2ClientRequest(SSL = false, PORT = 9590, token = " ");
        http2ClientRequest.start();
    }

    public void start() throws SSLException {

        final SslContext sslCtx;

        if (SSL) {
            log.debug("Configuring SSL");
            SslProvider provider = OpenSsl.isAlpnSupported() ? SslProvider.OPENSSL : SslProvider.JDK;
            sslCtx = SslContextBuilder.forClient()
                    .sslProvider(provider)
                    /* NOTE: the cipher filter may not include all ciphers required by the HTTP/2 specification.
                     * Please refer to the HTTP/2 specification for cipher requirements. */
                    .ciphers(Http2SecurityUtil.CIPHERS, SupportedCipherSuiteFilter.INSTANCE)
                    .trustManager(InsecureTrustManagerFactory.INSTANCE)
                    .applicationProtocolConfig(new ApplicationProtocolConfig(
                            ApplicationProtocolConfig.Protocol.ALPN,
                            // NO_ADVERTISE is currently the only mode supported by both OpenSsl and JDK providers.
                            ApplicationProtocolConfig.SelectorFailureBehavior.NO_ADVERTISE,
                            // ACCEPT is currently the only mode supported by both OpenSsl and JDK providers.
                            ApplicationProtocolConfig.SelectedListenerFailureBehavior.ACCEPT,
                            ApplicationProtocolNames.HTTP_2,
                            ApplicationProtocolNames.HTTP_1_1))
                    .build();
        } else {
            sslCtx = null;
        }

        EventLoopGroup workerGroup = new NioEventLoopGroup();
        Http2ClientInitializer initializer = new Http2ClientInitializer(sslCtx, Integer.MAX_VALUE);

        try {

            log.debug("Configure the client");
            Bootstrap b = new Bootstrap();
            b.group(workerGroup);
            b.channel(NioSocketChannel.class);
            b.option(ChannelOption.SO_KEEPALIVE, true);
            b.remoteAddress(HOST, PORT);
            b.handler(initializer);

            log.debug("Start the client");
            Channel channel = b.connect().syncUninterruptibly().channel();
            log.info("Connected to [" + HOST + ':' + PORT + ']');

            log.debug("Wait for the HTTP/2 upgrade to occur");
            Http2SettingsHandler http2SettingsHandler = initializer.settingsHandler();
            http2SettingsHandler.awaitSettings(5, TimeUnit.SECONDS);

            Http2ResponseHandler responseHandler = initializer.responseHandler();
            int streamId = 3;

            HttpScheme scheme = SSL ? HttpScheme.HTTPS : HttpScheme.HTTP;
            AsciiString hostName = new AsciiString(HOST + ':' + PORT);

            log.debug("Sending request(s)");

            if (URL != null) {

                log.debug("Create a simple GET request");

                FullHttpRequest request = new DefaultFullHttpRequest(HTTP_1_1, GET, URL);
                request.headers().add(HttpHeaderNames.AUTHORIZATION, "Bearer " + token);
                request.headers().add(HttpHeaderNames.HOST, hostName);
                request.headers().add(HttpConversionUtil.ExtensionHeaderNames.SCHEME.text(), scheme.name());
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.GZIP);
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.DEFLATE);
                responseHandler.put(streamId, channel.write(request), channel.newPromise());
                streamId += 2;
            }
            if (false) {
                // Create a simple POST request with a body.
                log.debug("Create a simple POST request with a body");
                FullHttpRequest request = new DefaultFullHttpRequest(HTTP_1_1, POST, URL,
                        wrappedBuffer(URLDATA.getBytes(CharsetUtil.UTF_8)));
                request.headers().add(HttpHeaderNames.AUTHORIZATION, "Bearer " + token);
                request.headers().add(HttpHeaderNames.HOST, hostName);
                request.headers().add(HttpConversionUtil.ExtensionHeaderNames.SCHEME.text(), scheme.name());
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.GZIP);
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.DEFLATE);
                responseHandler.put(streamId, channel.write(request), channel.newPromise());
            }
            if (false) {
                // Create a simple OPTIONS request.
                log.debug("Create a simple OPTIONS request with a body");
                FullHttpRequest request = new DefaultFullHttpRequest(HTTP_1_1, OPTIONS, URL);
                request.headers().add(HttpHeaderNames.AUTHORIZATION, "Bearer " + token);
                request.headers().add(HttpHeaderNames.HOST, hostName);
                request.headers().add(HttpConversionUtil.ExtensionHeaderNames.SCHEME.text(), scheme.name());
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.GZIP);
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.DEFLATE);
                responseHandler.put(streamId, channel.write(request), channel.newPromise());
                streamId += 2;
            }
            if (false) {
                // Create a simple HEAD request.
                log.debug("Create a simple HEAD request");
                FullHttpRequest request = new DefaultFullHttpRequest(HTTP_1_1, HEAD, URL);
                request.headers().add(HttpHeaderNames.AUTHORIZATION, "Bearer " + token);
                request.headers().add(HttpHeaderNames.HOST, hostName);
                request.headers().add(HttpConversionUtil.ExtensionHeaderNames.SCHEME.text(), scheme.name());
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.GZIP);
                request.headers().add(HttpHeaderNames.ACCEPT_ENCODING, HttpHeaderValues.DEFLATE);
                responseHandler.put(streamId, channel.write(request), channel.newPromise());
                streamId += 2;
            }
            log.debug("flushing the channel");
            channel.flush();
            responseHandler.awaitResponses(5, TimeUnit.SECONDS);
            log.debug("Finished HTTP/2 request(s)");

            log.debug("Wait until the connection is closed");
            channel.close().syncUninterruptibly();
        } catch (Exception e) {
            log.error("An Exception occurred " + e);
        } finally {
            workerGroup.shutdownGracefully();
        }
    }
}