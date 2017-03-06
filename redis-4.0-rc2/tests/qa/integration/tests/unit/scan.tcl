start_server {tags {"scan"}} {
    test "SCAN basic" {
        ssdbr flushdb
        ssdbr debug populate 1000
        for {set i 0} {$i < 1000} {incr i} {
            dumpto_ssdb_and_wait r "key:$i"
        }

        set cur 0
        set keys {}
        while 1 {
            set res [ssdbr scan $cur]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 1000 [llength $keys]
    }

    test "SCAN COUNT" {
        ssdbr flushdb
        ssdbr debug populate 1000
        for {set i 0} {$i < 1000} {incr i} {
            dumpto_ssdb_and_wait r "key:$i"
        }

        set cur 0
        set keys {}
        while 1 {
            set res [ssdbr scan $cur count 5]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 1000 [llength $keys]
    }

    test "SCAN MATCH" {
        ssdbr flushdb
        ssdbr debug populate 1000
        for {set i 0} {$i < 1000} {incr i} {
            dumpto_ssdb_and_wait r "key:$i"
        }

        set cur 0
        set keys {}
        while 1 {
            set res [ssdbr scan $cur match "key:1??"]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 100 [llength $keys]
    }

    foreach enc {intset hashtable} {
        test "SSCAN with encoding $enc" {
            # Create the Set
            ssdbr del set
            if {$enc eq {intset}} {
                set prefix ""
            } else {
                set prefix "ele:"
            }
            set elements {}
            for {set j 0} {$j < 100} {incr j} {
                lappend elements ${prefix}${j}
            }
            ssdbr sadd set {*}$elements

            # Verify that the encoding matches.
            assert {[ssdbr object encoding set] eq $enc}

            # Test SSCAN
            set cur 0
            set keys {}
            while 1 {
                set res [ssdbr sscan set $cur]
                set cur [lindex $res 0]
                set k [lindex $res 1]
                lappend keys {*}$k
                if {$cur == 0} break
            }

            set keys [lsort -unique $keys]
            assert_equal 100 [llength $keys]
        }
    }


    foreach enc {ziplist hashtable} {
        test "HSCAN with encoding $enc" {
            # Create the Hash
            ssdbr del hash
            if {$enc eq {ziplist}} {
                set count 30
            } else {
                set count 1000
            }
            set elements {}
            for {set j 0} {$j < $count} {incr j} {
                lappend elements key:$j $j
            }
            ssdbr hmset hash {*}$elements

            # Verify that the encoding matches.
            assert {[ssdbr object encoding hash] eq $enc}

            # Test HSCAN
            set cur 0
            set keys {}
            while 1 {
                set res [ssdbr hscan hash $cur]
                set cur [lindex $res 0]
                set k [lindex $res 1]
                lappend keys {*}$k
                if {$cur == 0} break
            }

            set keys2 {}
            foreach {k v} $keys {
                assert {$k eq "key:$v"}
                lappend keys2 $k
            }

            set keys2 [lsort -unique $keys2]
            assert_equal $count [llength $keys2]
        }
    }

    foreach enc {ziplist skiplist} {
        test "ZSCAN with encoding $enc" {
            # Create the Sorted Set
            ssdbr del zset
            if {$enc eq {ziplist}} {
                set count 30
            } else {
                set count 1000
            }
            set elements {}
            for {set j 0} {$j < $count} {incr j} {
                lappend elements $j key:$j
            }
            ssdbr zadd zset {*}$elements

            # Verify that the encoding matches.
            assert {[ssdbr object encoding zset] eq $enc}

            # Test ZSCAN
            set cur 0
            set keys {}
            while 1 {
                set res [ssdbr zscan zset $cur]
                set cur [lindex $res 0]
                set k [lindex $res 1]
                lappend keys {*}$k
                if {$cur == 0} break
            }

            set keys2 {}
            foreach {k v} $keys {
                assert {$k eq "key:$v"}
                lappend keys2 $k
            }

            set keys2 [lsort -unique $keys2]
            assert_equal $count [llength $keys2]
        }
    }

    test "SCAN guarantees check under write load" {
        ssdbr flushdb
        ssdbr debug populate 100

        # We start scanning here, so keys from 0 to 99 should all be
        # reported at the end of the iteration.
        set keys {}
        while 1 {
            set res [ssdbr scan $cur]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
            # Write 10 random keys at every SCAN iteration.
            for {set j 0} {$j < 10} {incr j} {
                ssdbr set addedkey:[randomInt 1000] foo
            }
        }

        set keys2 {}
        foreach k $keys {
            if {[string length $k] > 6} continue
            lappend keys2 $k
        }

        set keys2 [lsort -unique $keys2]
        assert_equal 100 [llength $keys2]
    }

    test "SSCAN with integer encoded object (issue #1345)" {
        set objects {1 a}
        ssdbr del set
        ssdbr sadd set {*}$objects
        set res [ssdbr sscan set 0 MATCH *a* COUNT 100]
        assert_equal [lsort -unique [lindex $res 1]] {a}
        set res [ssdbr sscan set 0 MATCH *1* COUNT 100]
        assert_equal [lsort -unique [lindex $res 1]] {1}
    }

    test "SSCAN with PATTERN" {
        ssdbr del mykey
        ssdbr sadd mykey foo fab fiz foobar 1 2 3 4
        set res [ssdbr sscan mykey 0 MATCH foo* COUNT 10000]
        lsort -unique [lindex $res 1]
    } {foo foobar}

    test "HSCAN with PATTERN" {
        ssdbr del mykey
        ssdbr hmset mykey foo 1 fab 2 fiz 3 foobar 10 1 a 2 b 3 c 4 d
        set res [ssdbr hscan mykey 0 MATCH foo* COUNT 10000]
        lsort -unique [lindex $res 1]
    } {1 10 foo foobar}

    test "ZSCAN with PATTERN" {
        ssdbr del mykey
        ssdbr zadd mykey 1 foo 2 fab 3 fiz 10 foobar
        set res [ssdbr zscan mykey 0 MATCH foo* COUNT 10000]
        lsort -unique [lindex $res 1]
    }

    test "ZSCAN scores: regression test for issue #2175" {
        ssdbr del mykey
        for {set j 0} {$j < 500} {incr j} {
            ssdbr zadd mykey 9.8813129168249309e-5 $j
        }
        set res [lindex [ssdbr zscan mykey 0] 1]
        set first_score [lindex $res 1]
        assert {$first_score != 0}
    }
}
